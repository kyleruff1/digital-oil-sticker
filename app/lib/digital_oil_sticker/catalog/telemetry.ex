defmodule DigitalOilSticker.Catalog.Telemetry do
  @moduledoc """
  Emits query SHAPE only — function atom, duration, cache hit/miss, error
  kind. Never a parameter value, id, or name (AC-13 log redaction).
  """

  @spec span(atom(), (-> result)) :: result when result: var
  def span(function, fun) do
    start = System.monotonic_time()
    :telemetry.execute([:dos, :catalog, :query, :start], %{system_time: System.system_time()}, %{function: function})

    try do
      result = fun.()

      :telemetry.execute(
        [:dos, :catalog, :query, :stop],
        %{duration: System.monotonic_time() - start},
        %{function: function, outcome: outcome_tag(result)}
      )

      result
    rescue
      e ->
        :telemetry.execute(
          [:dos, :catalog, :query, :exception],
          %{duration: System.monotonic_time() - start},
          %{function: function, kind: e.__struct__}
        )

        reraise e, __STACKTRACE__
    end
  end

  defp outcome_tag({:ok, %{status: status}}), do: status
  defp outcome_tag({:ok, _}), do: :ok
  defp outcome_tag({:error, kind}) when is_atom(kind), do: kind
  defp outcome_tag(_), do: :other
end
