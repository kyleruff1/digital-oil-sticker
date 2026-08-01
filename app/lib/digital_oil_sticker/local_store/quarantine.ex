defmodule DigitalOilSticker.LocalStore.Quarantine do
  @moduledoc """
  A record held aside because it failed a read-time integrity rule
  (DOS-M09-001 FR-12, DOS-M09-002 FR-8).

  A quarantine entry names the store, the record identifier (when one could
  be read), and the violated rule — and nothing else. Record contents are
  never carried here, so nothing personal can leak through inspection,
  logging, or error reports (INV-4). The struct deliberately has no field
  that could hold record content, and `Inspect` is derived to render only
  `store`, `rule`, and `id`.

  Quarantine is never repair and never deletion: the failing record stays in
  the raw payload, which remains exportable for recovery.
  """

  @derive {Inspect, only: [:store, :rule, :id]}
  @enforce_keys [:store, :rule]
  defstruct [:store, :id, :rule]

  @type t :: %__MODULE__{
          store: String.t(),
          id: String.t() | nil,
          rule: atom()
        }
end
