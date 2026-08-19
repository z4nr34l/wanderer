defmodule WandererApp.Character.Scopes do
  @moduledoc """
  Which ESI permissions a character actually granted, against the ones this deployment asks for.

  A token carries the scopes it was granted with, so a character authorised before a scope was
  added keeps working for everything else while quietly having nothing to offer the feature that
  needed the new scope. This is how the UI can say so instead of leaving people to guess.
  """

  @doc """
  The scopes a plain authorisation asks for.

  The wallet and admin tiers add to this; a character that granted only the base set is not stale
  just because it never had a reason to grant the wallet ones.
  """
  @spec required() :: [String.t()]
  def required do
    :ueberauth
    |> Application.get_env(Ueberauth, [])
    |> Keyword.get(:providers, [])
    |> Keyword.get(:eve)
    |> case do
      {_strategy, opts} -> opts |> Keyword.get(:default_scope, "") |> split()
      _ -> []
    end
  end

  @doc """
  What this character never granted, of what a plain authorisation asks for now.
  """
  @spec missing(map()) :: [String.t()]
  def missing(%{scopes: scopes}), do: required() -- split(scopes)
  def missing(_character), do: []

  @doc """
  Whether the character needs sending back through SSO to pick up scopes added since.
  """
  @spec stale?(map()) :: boolean()
  def stale?(character), do: missing(character) != []

  defp split(nil), do: []

  defp split(scopes) when is_binary(scopes),
    do: scopes |> String.split(~r/[\s,]+/, trim: true)

  defp split(scopes) when is_list(scopes), do: scopes
end
