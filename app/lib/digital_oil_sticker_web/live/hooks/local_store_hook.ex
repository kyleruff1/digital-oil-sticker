defmodule DigitalOilStickerWeb.LocalStoreHook do
  @moduledoc """
  on_mount hook for the `:garage` live_session: every LiveView gets the full
  LocalStore protocol (hydrate/ack/conflict interception + deadline/timeout
  infos) with zero duplicated code, and none of them can mutate the protocol
  assigns directly — `Session` is the sole mutator.
  """
  import Phoenix.LiveView
  alias DigitalOilStickerWeb.LocalStore.Session

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> Session.init()
     |> attach_hook(:local_store_events, :handle_event, &handle_protocol_event/3)
     |> attach_hook(:local_store_infos, :handle_info, &handle_protocol_info/2)}
  end

  defp handle_protocol_event("local_store:hydrate", params, socket) do
    {:halt, Session.handle_hydrate(socket, params)}
  end

  defp handle_protocol_event("local_store:ack", params, socket) do
    {:halt, Session.handle_ack(socket, params)}
  end

  defp handle_protocol_event("local_store:conflict", params, socket) do
    {:halt, Session.handle_conflict(socket, params)}
  end

  defp handle_protocol_event("local_store:persist_result", %{"result" => result}, socket) do
    granted = if result == "granted", do: true, else: if(result == "denied", do: false, else: nil)
    {:halt, Phoenix.Component.assign(socket, :persist_granted, granted)}
  end

  defp handle_protocol_event(_event, _params, socket), do: {:cont, socket}

  defp handle_protocol_info({:local_store_deadline, ref}, socket) do
    {:halt, Session.handle_deadline(socket, ref)}
  end

  defp handle_protocol_info({:local_store_ack_timeout, mutation_id}, socket) do
    {:halt, Session.handle_ack_timeout(socket, mutation_id)}
  end

  defp handle_protocol_info(_msg, socket), do: {:cont, socket}
end
