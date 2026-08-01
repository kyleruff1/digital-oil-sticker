defmodule DigitalOilSticker.CatalogRepo do
  @moduledoc """
  The ONLY Ecto repo in the deployed application (ADR-0004 §4, DOS-M09-004
  FR-16): a read-only handle onto the catalog SQLite artifact baked into the
  release image. There is deliberately no user/personal repo on the server —
  personal data lives in the browser (INV-23).

  Write prevention is layered four deep:
    1. `read_only: true` here — Ecto does not define insert/update/delete.
    2. `mode: :readonly` in runtime config — SQLITE_OPEN_READONLY.
    3. `after_connect` runs `PRAGMA query_only = ON` (runtime config).
    4. The artifact ships chmod 0444 inside the image.
  """
  use Ecto.Repo,
    otp_app: :digital_oil_sticker,
    adapter: Ecto.Adapters.SQLite3,
    read_only: true
end
