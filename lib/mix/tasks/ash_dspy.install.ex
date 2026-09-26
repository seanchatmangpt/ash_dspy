if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshDspy.Install do
    @moduledoc """
    Installs `ash_dspy` into the current project: adds the formatter plugin,
    and patches the target resource module to add
    `extensions: [AshDspy.Resource]` plus a starter `:dspy` block.
    """
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :ash_dspy,
        example: "mix ash_dspy.install --target MyApp.SomeResource",
        positional: [],
        schema: [target: :string],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      base =
        igniter
        |> Igniter.Project.Formatter.import_dep(:ash_dspy)
        |> Igniter.Project.Formatter.add_formatter_plugin(AshDspy.Formatter)

      case igniter.args.options[:target] do
        nil ->
          # No --target given (e.g. plain `mix igniter.install ash_dspy`) --
          # formatter is still wired up automatically; the resource/domain patch needs a
          # target module, so fall back to a real, disclosed manual-instructions notice
          # rather than guessing which module to patch.
          Igniter.add_notice(base, """
          AshDspy.Resource installed successfully!

          Add `extensions: [AshDspy.Resource]` to your Ash.Resource modules:

              use Ash.Resource,
                extensions: [AshDspy.Resource]

              dspy do
              end

          Or re-run with `--target MyApp.SomeResource` to patch a specific module automatically.
          """)

        target ->
          target_module = Igniter.Project.Module.parse(target)

          Igniter.Project.Module.find_and_update_module!(base, target_module, fn zipper ->
            zipper
            |> add_extension()
            |> add_starter_dsl_block()
          end)
      end
    end

    # Inserts `extensions: [AshDspy.Resource]` after the target module's `use
    # Ash.Resource` call. This is a single unconditional
    # insert, not a detect-or-append merge -- it does not check whether an `extensions:`
    # option already exists on that `use` call, so running install against a module that
    # already has one will add a second `extensions:` option rather than merging into the
    # first. Fine for the common case (patching a plain `use Ash.*` with no options yet);
    # a real detect-and-merge is a follow-up, not implemented here.
    defp add_extension(zipper) do
      Igniter.Code.Common.add_code(zipper, "extensions: [AshDspy.Resource]", placement: :after)
    end

    # Adds a minimal, real starter block for the primary section so the target module
    # compiles immediately after install rather than needing hand-authored DSL content.
    defp add_starter_dsl_block(zipper) do
      Igniter.Code.Common.add_code(
        zipper,
        """
        dspy do
        end
        """,
        placement: :after
      )
    end
  end
else
  defmodule Mix.Tasks.AshDspy.Install do
    @moduledoc "Installs `ash_dspy` -- Igniter is not a dependency of this project, so this task prints manual instructions instead of patching files."
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().info("""
      AshDspy.Resource: Igniter is not installed, so `ash_dspy.install` cannot
      patch files automatically. Add `extensions: [AshDspy.Resource]` to your
      Ash.Resource modules by hand:

          use Ash.Resource,
            extensions: [AshDspy.Resource]

          dspy do
          end
      """)
    end
  end
end
