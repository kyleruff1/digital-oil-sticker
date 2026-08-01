defmodule DigitalOilSticker.Repo do
  use Ecto.Repo,
    otp_app: :digital_oil_sticker,
    adapter: Ecto.Adapters.SQLite3
end
