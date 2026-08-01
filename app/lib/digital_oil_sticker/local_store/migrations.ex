defmodule DigitalOilSticker.LocalStore.Migrations do
  @moduledoc """
  Forward-only logical schema migrations (DOS-M09-001 FR-7/FR-8/FR-9,
  DOS-M09-002 FR-10/FR-11).

  Migration steps are pure, ordered functions from one logical version to
  the next, applied in sequence with no step skipped. There is no downgrade
  path: a payload at a version newer than the server's is a read-only
  signal, never a write — downgrading, dropping unknown fields, or writing
  at the older version is prohibited.

  `@migrations` maps a from-version to its step function
  (`data -> {:ok, data}`). It is empty while version 1 is the only released
  version; every future version bump adds a step and a fixture and never
  edits a released step.
  """

  # from_version => (data -> {:ok, data} | {:error, term()})
  @migrations %{}

  @type outcome :: :unchanged | :migrated

  @spec migrate(map(), pos_integer(), pos_integer()) ::
          {:ok, map(), outcome()}
          | {:error, {:newer_than_server, pos_integer()} | {:migration_failed, pos_integer()}}
  def migrate(data, version, version) when is_integer(version) and version > 0 do
    {:ok, data, :unchanged}
  end

  def migrate(_data, from_version, to_version)
      when is_integer(from_version) and is_integer(to_version) and from_version > to_version do
    {:error, {:newer_than_server, from_version}}
  end

  # While @migrations is empty, every forward request fails at its first
  # step by definition; the compile-time branch keeps the type checker from
  # flagging clauses it can prove dead. Registering the first migration
  # activates the real ordered walk unchanged.
  if map_size(@migrations) == 0 do
    def migrate(_data, from_version, to_version)
        when is_integer(from_version) and is_integer(to_version) and
               from_version > 0 and from_version < to_version do
      {:error, {:migration_failed, from_version}}
    end
  else
    def migrate(data, from_version, to_version)
        when is_integer(from_version) and is_integer(to_version) and
               from_version > 0 and from_version < to_version do
      Enum.reduce_while(from_version..(to_version - 1)//1, {:ok, data, :migrated}, fn
        version, {:ok, acc, outcome} ->
          case apply_step(version, acc) do
            {:ok, migrated} -> {:cont, {:ok, migrated, outcome}}
            {:error, _reason} -> {:halt, {:error, {:migration_failed, version}}}
          end
      end)
    end

    defp apply_step(version, data) do
      case Map.fetch(@migrations, version) do
        {:ok, step} -> step.(data)
        :error -> {:error, :missing_step}
      end
    end
  end
end
