use Mix.Config

config :juliet,
  hosts: ["localhost"],

  listeners: [
    {Juliet.C2S, [
      port: 5222,
      acceptors: 3, #defaults to 100
      #starttls: true, # don't need this if starttls_required is true
      starttls_required: true,
      certfile: System.get_env("CERT_PATH")
    ]}
  ]
