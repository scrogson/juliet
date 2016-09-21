defmodule Juliet.C2S do

  @behaviour :gen_statem
  @behaviour :ranch_protocol

  use Romeo.XML
  alias Romeo.XML
  alias Juliet.StreamParser

  require Logger

  defmodule State do
    defstruct authenticated: false,
              certfile: nil,
              parser: nil,
              resource: nil,
              server: nil,
              socket: nil,
              starttls: false,
              starttls_required: false,
              stream_id: nil,
              transport: nil,
              user: nil
  end

  def start_link(ref, socket, transport, opts \\ []) do
    :proc_lib.start_link(__MODULE__, :init, [[ref, socket, transport, opts]])
  end

  def init([ref, socket, transport, opts]) do
    :ok = :proc_lib.init_ack({:ok, self()})
    :ok = :ranch.accept_ack(ref)
    :ok = transport.setopts(socket, [active: :once])

    {:ok, parser} = StreamParser.start_link()

    certfile = Keyword.get(opts, :certfile)
    starttls = Keyword.get(opts, :starttls, false)
    starttls_required = Keyword.get(opts, :starttls_required, false)

    :gen_statem.enter_loop(__MODULE__, [], :handle_event_function, :await_stream, %State{
      certfile: certfile,
      parser: parser,
      socket: socket,
      starttls: starttls,
      starttls_required: starttls_required,
      transport: transport
    })
  end

  def handle_event(:cast, {:xmlstreamstart, "stream:stream", attrs}, :await_stream, state) do
    # TODO: verify that the `to` is in the configured hosts
    # hosts = Application.get_env(:juliet, :hosts)

    {"to", server} = List.keyfind(attrs, "to", 0)
    stream_id = stream_id()

    :ok = send_packet(state, start_stream(server, stream_id))
    {:ok, next_state} = send_stream_features(state)

    {:next_state, next_state, %{state | server: server, stream_id: stream_id}}
  end

  def handle_event(:cast, xmlel(name: "starttls"), :await_feature_request, %{certfile: certfile, socket: socket, transport: transport} = state) do
    :ok = send_packet(state, xmlel(name: "proceed", attrs: [{"xmlns", ns_tls()}]))
    :ok = transport.setopts(socket, [active: false])
    {:ok, socket} = :ssl.ssl_accept(socket, [certfile: certfile])
    :ok = :ranch_ssl.setopts(socket, [active: :once])
    :ok = StreamParser.reset(state.parser)

    {:next_state, :await_stream, %{state | socket: socket, transport: :ranch_ssl}}
  end

  def handle_event(:cast, xmlel(name: "auth") = xml, :await_authentication, state) do
    authenticate(XML.attr(xml, "mechanism"), xml, state)
  end

  def handle_event(:cast, xmlel(name: "iq") = xml, :await_feature_request, %{socket: socket, transport: transport} = state) do
    id = XML.attr(xml, "id")

    if XML.attr(xml, "type") == "set" do
      resource = get_or_generate_resource(xml)
      jid = xmlel(name: "jid", children: [xmlcdata(content: jid(state, resource))])
      bind = xmlel(name: "bind", attrs: [{"xmlns", ns_bind()}], children: [jid])

      :ok = send_packet(state, xmlel(name: "iq", attrs: [
         {"id", id}, {"type", "result"}], children: [bind]))

      {:next_state, :session_established, %{state | resource: resource}}
    else
      :stop
    end
  end

  def handle_event(:cast, xmlel(name: "message") = xml, :session_established, state) do
    :keep_state_and_data
  end
  def handle_event(:cast, xmlel(name: "presence") = xml, :session_established, state) do
    case XML.attr(xml, "type") do
      nil ->
        Logger.info "#{jid(state, state.resource)} now online."
      _  -> :ok
    end

    :keep_state_and_data
  end
  def handle_event(:cast, xmlel(name: "iq") = xml, :session_established, _state) do
    Logger.warn "TODO: Handle IQ messages: #{inspect xml}"
    :keep_state_and_data
  end

  def handle_event(:info, {:xmlstreamstart, "stream:stream", _} = stanza, _state_name, _state) do
    :gen_statem.cast(self(), stanza)
    :keep_state_and_data
  end

  def handle_event(:info, {:xmlstreamelement, stanza}, _state_name, _state) do
    :gen_statem.cast(self(), stanza)
    :keep_state_and_data
  end

  def handle_event(:info, {mode, socket, data}, state_name, state) when mode in [:tcp, :ssl] do
    %{transport: transport, parser: parser} = state

    Logger.debug "INCOMING > #{data}"

    :ok = parse_packet(parser, data)
    :ok = transport.setopts(socket, [active: :once])
    :keep_state_and_data
  end

  def handle_event(:info, {reason, _}, _state_name, _state)
    when reason in [:tcp_closed, :ssl_closed] do
    Logger.debug "Connection closed."
    :stop
  end

  def handle_event(:info, msg, _state_name, _state) do
    Logger.warn "Received unhandled message: #{inspect msg}"
    :keep_state_and_data
  end

  def handle_event({:call, _from}, content, _state_name, _state) do
    :ok = :gen_statem.cast(self(), content)
    :keep_state_and_data
  end

  def code_change(_old_vsn, old_state, old_data, _extra) do
    {:handle_event_function, old_state, old_data}
  end

  def terminate(_reason, _state_name, _state) do
    :ok
  end

  ## Private

  defp parse_packet(parser, packet) do
    :ok = StreamParser.parse(parser, packet)
  end

  defp send_packet(%{transport: transport, socket: socket}, packet) when is_binary(packet) do
    Logger.debug "OUTGOING > #{packet}"
    :ok = transport.send(socket, packet)
  end
  defp send_packet(state, packet) do
    send_packet(state, Romeo.Stanza.to_xml(packet))
  end

  defp start_stream(server, id) do
    xmlstreamstart(name: "stream:stream",
     attrs: [
       {"id", id},
       {"to", server},
       {"version", "1.0"},
       {"xml:lang", "en"},
       {"xmlns", ns_jabber_server()},
       {"xmlns:stream", ns_xmpp()}
     ])
  end

  defp stream_features(features) do
    xmlel(name: "stream:features", children: features)
  end

  defp mechanisms do
    xmlel(name: "mechanisms", attrs: [{"xmlns", ns_sasl()}], children: [
      xmlel(name: "mechanism", children: [xmlcdata(content: "PLAIN")])
    ])
  end

  defp starttls(%{starttls_required: required}) do
    children = if required, do: [xmlel(name: "required")], else: []
    xmlel(name: "starttls", attrs: [{"xmlns", ns_tls()}], children: children)
  end

  defp stream_id, do: "#{System.system_time(:nanoseconds)}"

  defp send_stream_features(%{authenticated: false, starttls_required: true, transport: :ranch_tcp} = state) do
    :ok = send_packet(state, stream_features([starttls(state)]))
    {:ok, :await_feature_request}
  end
  defp send_stream_features(%{authenticated: false, transport: :ranch_ssl} = state) do
    :ok = send_packet(state, stream_features([mechanisms()]))
    {:ok, :await_authentication}
  end
  defp send_stream_features(%{authenticated: true} = state) do
    :ok = send_packet(state, stream_features([bind(), session()]))
    {:ok, :await_feature_request}
  end

  defp bind do
    xmlel(name: "bind", attrs: [{"xmlns", ns_bind()}])
  end

  defp session do
    xmlel(name: "session", attrs: [{"xmlns", ns_session()}], children: [
      xmlel(name: "optional")
    ])
  end

  defp authenticate("PLAIN", xml, state) do
    sasl_attrs = [{"xmlns", ns_sasl()}]
    case decode_plain_credentials(xml) do
      [user, _password] ->
        # TODO: Lookup user and compare password via SASL SCRAM
        # https://tools.ietf.org/html/rfc5802
        packet = xmlel(name: "success", attrs: sasl_attrs)
        :ok = send_packet(state, packet)
        :ok = StreamParser.reset(state.parser)

        {:next_state, :await_stream, %{state | authenticated: true, user: user}}
      _ ->
        packet = xmlel(name: "failure", attrs: sasl_attrs, children: [xmlel(name: "not-authorized")])
        :ok = send_packet(state, packet)

        {:next_state, :await_authentication, state}
    end
  end

  defp decode_plain_credentials(xml) do
    xml
    |> XML.cdata()
    |> Base.decode64!()
    |> String.split(<<0>>)
    |> tl()
  end

  defp get_or_generate_resource(xml) do
    bind = XML.subelement(xml, "bind")
    case XML.subelement(bind, "resource") do
      nil ->
        UUID.uuid4()
      xmlel(name: "resource", children: [xmlcdata(content: resource)]) ->
       resource
    end
  end

  defp jid(%{user: user, server: server}, resource) do
    "#{user}@#{server}/#{resource}"
  end

  defp close(%{transport: transport, socket: socket}) do
    :ok = transport.send(socket, "</stream:stream>")
    :ok = transport.close(socket)
  end
end
