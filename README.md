# PxImports

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `px_imports` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:px_imports, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/px_imports>.

{:req_llm, git: "https://github.com/agentjido/req_llm.git", override: true},

mix igniter.install ash,ash_phoenix \
 ,ash_json_api,ash_postgres \
 ,ash_authentication,ash_authentication_phoenix \
 ,ash_admin,ash_oban ,oban_web,live_debugger \
 ,tidewave,ash_ai, usage_rules --setup --yes
