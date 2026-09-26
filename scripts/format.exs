# Canonical formatting pass for ash_dspy (consumer scaffold).
#
# Why not `mix format`: its write mode runs the import_deps formatter plugins,
# whose output for the generated installer's heredoc+opts call does not converge
# with `mix format --check-formatted`'s own plain-format pipeline (witnessed:
# write mode is stable at the joined form, check mode stably demands the split
# form). This script is the check-mode pipeline verbatim: Code.format_string! +
# a single trailing newline, applied to the same inputs .formatter.exs names.
# Sync procedure: render (see README "Regeneration") -> mix run scripts/format.exs
# -> mix format --check-formatted.

inputs =
  ["mix.exs", ".formatter.exs"] ++
    Path.wildcard("{config,lib,test,scripts}/**/*.{ex,exs}") ++
    Path.wildcard("*.{ex,exs}")

changed =
  Enum.map(inputs |> Enum.uniq() |> Enum.sort(), fn path ->
    case File.read(path) do
      {:ok, src} ->
        formatted =
          src
          |> Code.format_string!(file: path)
          |> IO.iodata_to_binary()
          |> Kernel.<>("\n")

        if formatted != src do
          File.write!(path, formatted)
          path
        end

      {:error, _} ->
        nil
    end
  end)
  |> Enum.reject(&is_nil/1)

Enum.each(changed, fn path -> IO.puts("formatted #{path}") end)
IO.puts("format pass complete: #{length(changed)} file(s) changed")
