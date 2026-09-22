defmodule Lens.AnalysisTest do
  use Lens.DataCase, async: true

  alias Lens.Analysis

  describe "targets" do
    @valid_target_attrs %{
      security_code: "7203",
      market: "TSE Prime",
      display_name: "Toyota Motor Corp (Synthetic)",
      sector: "Transportation Equipment",
      tags: ["automotive", "large-cap"],
      source_reference: "EDINET filing #12345",
      verified_at: ~U[2024-01-15 10:00:00Z]
    }

    test "create_target/1 with valid attributes creates a target preserving text security code" do
      attrs = Map.put(@valid_target_attrs, :security_code, "07203.T")
      assert {:ok, target} = Analysis.create_target(attrs)

      assert target.security_code == "07203.T"
      assert target.market == "TSE Prime"
      assert target.display_name == "Toyota Motor Corp (Synthetic)"
      assert target.sector == "Transportation Equipment"
      assert target.tags == ["automotive", "large-cap"]
      assert target.active == true
      assert target.source_reference == "EDINET filing #12345"

      assert DateTime.truncate(target.verified_at, :second) == ~U[2024-01-15 10:00:00Z]
    end

    test "create_target/1 rejects duplicate security codes" do
      assert {:ok, _target} = Analysis.create_target(@valid_target_attrs)

      assert {:error, changeset} =
               Analysis.create_target(%{@valid_target_attrs | display_name: "Another Name"})

      assert "has already been taken" in errors_on(changeset).security_code
    end

    test "create_target/1 validates required attributes and bounded tags" do
      assert {:error, changeset} = Analysis.create_target(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.security_code
      assert "can't be blank" in errors.market
      assert "can't be blank" in errors.display_name
      assert "can't be blank" in errors.sector

      too_many_tags = Enum.map(1..15, &"tag#{&1}")

      assert {:error, changeset} =
               Analysis.create_target(Map.put(@valid_target_attrs, :tags, too_many_tags))

      assert "should have at most 10 item(s)" in errors_on(changeset).tags
    end

    test "update_target/2 updates target attributes" do
      assert {:ok, target} = Analysis.create_target(@valid_target_attrs)

      assert {:ok, updated} =
               Analysis.update_target(target, %{display_name: "Updated Name (Synthetic)"})

      assert updated.display_name == "Updated Name (Synthetic)"
    end

    test "deactivate_target/1 non-destructively deactivates target" do
      assert {:ok, target} = Analysis.create_target(@valid_target_attrs)
      assert target.active == true

      assert {:ok, deactivated} = Analysis.deactivate_target(target)
      assert deactivated.active == false
      assert deactivated.id == target.id
    end
  end

  describe "membership intervals" do
    setup do
      {:ok, target} =
        Analysis.create_target(%{
          security_code: "6758",
          market: "TSE Prime",
          display_name: "Sony Group (Synthetic)",
          sector: "Electric Appliances"
        })

      %{target: target}
    end

    test "create_membership/2 creates valid membership interval", %{target: target} do
      attrs = %{
        effective_from: ~D[2020-01-01],
        effective_to: ~D[2023-12-31],
        source_reference: "Annual constituent review 2020",
        verified_at: ~U[2020-01-01 00:00:00Z]
      }

      assert {:ok, membership} = Analysis.create_membership(target, attrs)
      assert membership.target_id == target.id
      assert membership.index_name == "nikkei_225"
      assert membership.effective_from == ~D[2020-01-01]
      assert membership.effective_to == ~D[2023-12-31]
      assert membership.source_reference == "Annual constituent review 2020"
    end

    test "create_membership/2 rejects invalid interval where effective_to < effective_from", %{
      target: target
    } do
      attrs = %{
        effective_from: ~D[2023-01-01],
        effective_to: ~D[2022-12-31]
      }

      assert {:error, changeset} = Analysis.create_membership(target, attrs)

      assert "must be on or after effective_from" in errors_on(changeset).effective_to
    end

    test "create_membership/2 rejects overlapping intervals for same target", %{target: target} do
      assert {:ok, _m1} =
               Analysis.create_membership(target, %{
                 effective_from: ~D[2020-01-01],
                 effective_to: ~D[2022-12-31]
               })

      # Overlapping interval 2022-06-01 to 2024-01-01
      assert {:error, changeset} =
               Analysis.create_membership(target, %{
                 effective_from: ~D[2022-06-01],
                 effective_to: ~D[2024-01-01]
               })

      assert "overlaps with an existing membership interval" in errors_on(changeset).effective_from
    end
  end

  describe "as-of membership lookup" do
    test "list_targets/1 with as_of option returns active members as of date" do
      {:ok, target_a} =
        Analysis.create_target(%{
          security_code: "9983",
          market: "TSE Prime",
          display_name: "Fast Retailing (Synthetic)",
          sector: "Retail Trade"
        })

      {:ok, target_b} =
        Analysis.create_target(%{
          security_code: "9984",
          market: "TSE Prime",
          display_name: "SoftBank Group (Synthetic)",
          sector: "Information & Communication"
        })

      # Target A member from 2020-01-01 to 2023-12-31
      {:ok, _} =
        Analysis.create_membership(target_a, %{
          effective_from: ~D[2020-01-01],
          effective_to: ~D[2023-12-31]
        })

      # Target B member from 2022-01-01 (ongoing)
      {:ok, _} =
        Analysis.create_membership(target_b, %{
          effective_from: ~D[2022-01-01],
          effective_to: nil
        })

      # As of 2023-06-01: both targets are members
      results_2023 = Analysis.list_targets(as_of: ~D[2023-06-01])
      target_ids_2023 = Enum.map(results_2023, & &1.id)
      assert target_a.id in target_ids_2023
      assert target_b.id in target_ids_2023

      # As of 2024-06-01: Target A is no longer a member, Target B remains
      results_2024 = Analysis.list_targets(as_of: ~D[2024-06-01])
      target_ids_2024 = Enum.map(results_2024, & &1.id)
      refute target_a.id in target_ids_2024
      assert target_b.id in target_ids_2024
    end
  end
end
