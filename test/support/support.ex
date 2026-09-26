# Lane 9 test support loader.
#
# mix.exs (lane 2) does not add test/support to elixirc_paths, so each of our
# test files requires THIS file once; it in turn requires the real support
# modules below. Code.require_file/1 is idempotent per path on a node, which
# keeps concurrent async test modules safe.

["corpus.ex", "implementations.ex", "fixtures.ex", "seams.ex"]
|> Enum.each(fn file ->
  path = Path.expand(file, __DIR__)
  Code.require_file(path)
end)
