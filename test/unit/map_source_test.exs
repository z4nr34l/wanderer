defmodule WandererApp.Map.Operations.SourceTest do
  @moduledoc """
  Reading another map's contents straight from the map, rather than from a file.

  The remote half is an HTTP call and is left to the integration side; what matters here is that
  a map next door is read through the same key its own API would have demanded, and that a
  mistyped address is refused rather than turned into a request.
  """

  use WandererApp.DataCase

  alias WandererApp.Map.Operations.Source

  describe "fetch/1 for a map on this instance" do
    test "hands over the map's contents to whoever holds its key" do
      map = insert(:map, %{public_api_key: "the-key"})

      assert {:ok, document} = Source.fetch(%{base_url: "", slug: map.slug, token: "the-key"})

      assert document["version"] == 2
      assert is_list(document["systems"])
      assert is_list(document["connections"])
    end

    test "refuses the wrong key, and a map that hands out no key at all" do
      map = insert(:map, %{public_api_key: "the-key"})
      keyless = insert(:map, %{public_api_key: nil})

      assert {:error, :forbidden} =
               Source.fetch(%{base_url: "", slug: map.slug, token: "not-the-key"})

      assert {:error, :forbidden} =
               Source.fetch(%{base_url: "", slug: keyless.slug, token: "anything"})
    end

    test "says so when there is no such map" do
      assert {:error, :no_such_map} =
               Source.fetch(%{base_url: "", slug: "nothing-by-that-name", token: "the-key"})
    end
  end

  describe "fetch/1 with an address somebody typed" do
    test "wants a slug and a key before it goes anywhere" do
      assert {:error, :invalid} = Source.fetch(%{base_url: "", slug: "", token: "the-key"})
      assert {:error, :invalid} = Source.fetch(%{base_url: "", slug: "a-map", token: ""})
      assert {:error, :invalid} = Source.fetch(%{slug: "a-map"})
    end

    test "refuses an address that is not the web" do
      assert {:error, :invalid} =
               Source.fetch(%{base_url: "ftp://elsewhere", slug: "a-map", token: "the-key"})
    end
  end

  describe "message/1" do
    test "says something a person can act on" do
      assert Source.message(:forbidden) =~ "key"
      assert Source.message(:no_such_map) =~ "slug"
      assert Source.message(:unreachable) =~ "reach"
      assert Source.message(:something_new) =~ "Could not read"
    end
  end
end
