defmodule WandererApp.FitsTest do
  @moduledoc """
  The mass maths behind the rolling calculator. Everything here is the pure half of
  `WandererApp.Fits` - what ESI returns is fed in rather than fetched.
  """

  use ExUnit.Case, async: true

  alias WandererApp.Fits

  defp part(attrs) do
    %{
      name: Keyword.get(attrs, :name, "Module"),
      addition: Keyword.get(attrs, :addition, 0),
      percentage: Keyword.get(attrs, :percentage, 0),
      own_mass: Keyword.get(attrs, :own_mass, 0),
      propulsion?: Keyword.get(attrs, :propulsion?, false)
    }
  end

  defp prop_mod(addition \\ 50_000_000) do
    part(name: "500MN Microwarpdrive II", addition: addition, propulsion?: true)
  end

  defp higgs, do: part(name: "Medium Higgs Anchor I", percentage: 100)

  describe "compute_masses/2" do
    test "a bare hull weighs what the hull weighs" do
      assert %{cold_mass: 11_280_000, hot_mass: 11_280_000, prop_module: nil} =
               Fits.compute_masses(11_280_000, [])
    end

    test "the prop mod only counts towards the hot number" do
      assert %{
               cold_mass: 11_280_000,
               hot_mass: 61_280_000,
               prop_module: "500MN Microwarpdrive II"
             } =
               Fits.compute_masses(11_280_000, [prop_mod()])
    end

    test "a Higgs Anchor doubles the ship, prop mod included" do
      # this is the case that was wrong: the rig was ignored, so both numbers came out at half
      assert %{cold_mass: 22_560_000, hot_mass: 122_560_000} =
               Fits.compute_masses(11_280_000, [prop_mod(), higgs()])
    end

    test "plates are added before the percentage is applied" do
      plate = part(name: "1600mm Steel Plates II", addition: 3_750_000)

      assert %{cold_mass: 30_060_000, hot_mass: 130_060_000} =
               Fits.compute_masses(11_280_000, [plate, prop_mod(), higgs()])
    end

    test "each fitted copy of a module counts" do
      plate = part(name: "1600mm Steel Plates II", addition: 3_750_000)

      assert %{cold_mass: 18_780_000} = Fits.compute_masses(11_280_000, [plate, plate])
    end

    test "a T3 cruiser carries the mass of its subsystems" do
      subsystem = part(name: "Loki Core - Augmented Nuclear Reactor", own_mass: 1_200_000)

      assert %{cold_mass: 32_400_000} =
               Fits.compute_masses(13_800_000, [subsystem, subsystem, higgs()])
    end

    test "the heaviest prop mod is the one that gets used" do
      assert %{prop_module: "500MN Microwarpdrive II", hot_mass: 61_280_000} =
               Fits.compute_masses(11_280_000, [
                 prop_mod(5_000_000) |> Map.put(:name, "50MN"),
                 prop_mod()
               ])
    end
  end

  describe "parse_eft/1" do
    test "reads the hull and drops charges, empty slots and cargo" do
      fit = """
      [Thorax, Roller]
      Damage Control II
      1600mm Steel Plates II
      [Empty Low slot]

      500MN Quad LiF Restrained Microwarpdrive
      Warp Disruptor II, Optimal Range Script

      Medium Higgs Anchor I

      Hobgoblin II x5
      Nanite Repair Paste x50
      """

      assert {:ok, %{ship_name: "Thorax", items: items}} = Fits.parse_eft(fit)

      assert items == [
               "Damage Control II",
               "1600mm Steel Plates II",
               "500MN Quad LiF Restrained Microwarpdrive",
               "Warp Disruptor II",
               "Medium Higgs Anchor I"
             ]
    end

    test "keeps duplicates so two of a module weigh twice as much" do
      fit = """
      [Thorax, Roller]
      1600mm Steel Plates II
      1600mm Steel Plates II
      """

      assert {:ok, %{items: ["1600mm Steel Plates II", "1600mm Steel Plates II"]}} =
               Fits.parse_eft(fit)
    end

    test "rejects anything that is not an EFT block" do
      assert {:error, :ship_not_found} = Fits.parse_eft("not a fit")
      assert {:error, :invalid_fit} = Fits.parse_eft(nil)
    end
  end
end
