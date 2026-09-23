defmodule Lens.AnalysisTest do
  use Lens.DataCase, async: true

  alias Lens.Analysis
  alias Lens.Analysis.Target
  alias Lens.Repo

  defp valid_target_attrs(custom \\ %{}) do
    Map.merge(
      %{
        security_code: "CODE-#{System.unique_integer([:positive])}",
        market: "TSE Prime",
        display_name: "Toyota Motor Corp (Synthetic)",
        sector: "Transportation Equipment",
        tags: ["automotive", "large-cap"],
        source_reference: "EDINET filing #12345",
        verified_at: ~U[2024-01-15 10:00:00Z]
      },
      custom
    )
  end

  describe "targets" do
    test "create_target/1 with valid attributes creates a target preserving text security code" do
      attrs = valid_target_attrs(%{security_code: "07203.T"})
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

    test "create_target/1 applies non-null defaults when fields are omitted" do
      attrs = valid_target_attrs() |> Map.drop([:tags, :active])

      assert {:ok, target} = Analysis.create_target(attrs)
      assert target.tags == []
      assert target.active == true
    end

    test "fetch_target/1 and get_target!/1" do
      attrs = valid_target_attrs()
      assert {:ok, target} = Analysis.create_target(attrs)

      assert {:ok, fetched} = Analysis.fetch_target(target.id)
      assert fetched.id == target.id

      assert Analysis.fetch_target("invalid-uuid") == :error
      assert Analysis.fetch_target(Ecto.UUID.generate()) == :error

      assert Analysis.get_target!(target.id).id == target.id

      assert_raise Ecto.NoResultsError, fn ->
        Analysis.get_target!(Ecto.UUID.generate())
      end
    end

    test "create_target/1 rejects duplicate security codes" do
      attrs = valid_target_attrs()
      assert {:ok, _target} = Analysis.create_target(attrs)

      assert {:error, changeset} =
               Analysis.create_target(Map.put(attrs, :display_name, "Another Name"))

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
               Analysis.create_target(valid_target_attrs(%{tags: too_many_tags}))

      assert "should have at most 10 item(s)" in errors_on(changeset).tags

      assert {:error, changeset2} =
               Analysis.create_target(valid_target_attrs(%{tags: "not-a-list"}))

      assert "is invalid" in errors_on(changeset2).tags

      long_tag = String.duplicate("a", 60)

      assert {:error, changeset3} =
               Analysis.create_target(valid_target_attrs(%{tags: [long_tag]}))

      assert "contains invalid tag elements" in errors_on(changeset3).tags

      assert {:error, changeset4} =
               Analysis.create_target(valid_target_attrs(%{tags: [123]}))

      assert "is invalid" in errors_on(changeset4).tags

      for field <- [:tags, :active] do
        assert {:error, nil_changeset} =
                 Analysis.create_target(valid_target_attrs(%{field => nil}))

        assert "can't be blank" in Map.fetch!(errors_on(nil_changeset), field)
      end
    end

    test "create_target/1 accepts source references up to 1000 characters" do
      assert {:ok, target} =
               Analysis.create_target(
                 valid_target_attrs(%{source_reference: String.duplicate("a", 1000)})
               )

      assert String.length(target.source_reference) == 1000

      assert {:error, changeset} =
               Analysis.create_target(
                 valid_target_attrs(%{source_reference: String.duplicate("a", 1001)})
               )

      assert "should be at most 1000 character(s)" in errors_on(changeset).source_reference
    end

    test "update_target/2 updates target attributes" do
      assert {:ok, target} = Analysis.create_target(valid_target_attrs())

      assert {:ok, updated} =
               Analysis.update_target(target, %{display_name: "Updated Name (Synthetic)"})

      assert updated.display_name == "Updated Name (Synthetic)"
    end

    test "deactivate_target/1 non-destructively deactivates target" do
      assert {:ok, target} = Analysis.create_target(valid_target_attrs())
      assert target.active == true

      assert {:ok, deactivated} = Analysis.deactivate_target(target)
      assert deactivated.active == false
      assert deactivated.id == target.id
    end
  end

  describe "membership intervals" do
    setup do
      {:ok, target} =
        Analysis.create_target(valid_target_attrs(%{display_name: "Sony Group (Synthetic)"}))

      %{target: target}
    end

    test "create_membership/2 creates valid membership interval and list_memberships/1 lists it",
         %{target: target} do
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

      memberships = Analysis.list_memberships(target.id)
      assert length(memberships) == 1
      assert hd(memberships).id == membership.id
    end

    test "updating an existing membership interval validates self-overlap exclusion", %{
      target: target
    } do
      {:ok, membership} =
        Analysis.create_membership(target, %{
          effective_from: ~D[2020-01-01],
          effective_to: ~D[2023-12-31]
        })

      changeset =
        membership
        |> Lens.Analysis.Membership.changeset(%{effective_to: ~D[2024-01-01]})
        |> Lens.Analysis.Membership.validate_no_overlapping_intervals()

      assert {:ok, updated} = Lens.Repo.update(changeset)
      assert updated.effective_to == ~D[2024-01-01]
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

    test "database constraint rejects overlapping intervals atomically", %{target: target} do
      assert {:ok, _membership} =
               Analysis.create_membership(target, %{
                 effective_from: ~D[2020-01-01],
                 effective_to: ~D[2022-12-31]
               })

      changeset =
        Lens.Analysis.Membership.changeset(%Lens.Analysis.Membership{}, %{
          target_id: target.id,
          effective_from: ~D[2022-06-01],
          effective_to: ~D[2024-01-01]
        })

      assert {:error, changeset} = Lens.Repo.insert(changeset)

      assert "overlaps with an existing membership interval" in errors_on(changeset).effective_from
    end

    test "create_membership/2 rejects a null index name", %{target: target} do
      assert {:error, changeset} =
               Analysis.create_membership(target, %{
                 index_name: nil,
                 effective_from: ~D[2020-01-01]
               })

      assert "can't be blank" in errors_on(changeset).index_name
    end

    test "create_membership/2 accepts source references up to 1000 characters", %{target: target} do
      assert {:ok, membership} =
               Analysis.create_membership(target, %{
                 effective_from: ~D[2020-01-01],
                 source_reference: String.duplicate("a", 1000)
               })

      assert String.length(membership.source_reference) == 1000
    end

    test "update_membership/2 closes an open interval", %{target: target} do
      assert {:ok, membership} =
               Analysis.create_membership(target, %{effective_from: ~D[2020-01-01]})

      assert {:ok, closed} =
               Analysis.update_membership(membership, %{effective_to: ~D[2024-09-30]})

      assert closed.effective_to == ~D[2024-09-30]
    end
  end

  describe "as-of membership lookup" do
    test "list_targets/1 preserves security-code ordering with an as_of filter" do
      lower_code_target =
        Repo.insert!(%Target{
          id: "00000000-0000-0000-0000-000000000002",
          security_code: "1000.T",
          market: "TSE Prime",
          display_name: "Lower Code (Synthetic)",
          sector: "Services"
        })

      higher_code_target =
        Repo.insert!(%Target{
          id: "00000000-0000-0000-0000-000000000001",
          security_code: "2000.T",
          market: "TSE Prime",
          display_name: "Higher Code (Synthetic)",
          sector: "Services"
        })

      for target <- [lower_code_target, higher_code_target] do
        assert {:ok, _} =
                 Analysis.create_membership(target, %{effective_from: ~D[2020-01-01]})
      end

      security_codes =
        Analysis.list_targets(as_of: ~D[2024-01-01])
        |> Enum.map(& &1.security_code)

      assert security_codes == ["1000.T", "2000.T"]
    end

    test "list_targets/1 with as_of option supports Date and ISO datetime, and rejects invalid values" do
      {:ok, target_a} =
        Analysis.create_target(
          valid_target_attrs(%{
            display_name: "Fast Retailing (Synthetic)"
          })
        )

      {:ok, target_b} =
        Analysis.create_target(
          valid_target_attrs(%{
            display_name: "SoftBank Group (Synthetic)"
          })
        )

      {:ok, _} =
        Analysis.create_membership(target_a, %{
          effective_from: ~D[2020-01-01],
          effective_to: ~D[2023-12-31]
        })

      {:ok, _} =
        Analysis.create_membership(target_b, %{
          effective_from: ~D[2022-01-01],
          effective_to: nil
        })

      # As of Date: both targets
      results_date = Analysis.list_targets(as_of: ~D[2023-06-01])
      ids_date = Enum.map(results_date, & &1.id)
      assert target_a.id in ids_date
      assert target_b.id in ids_date

      # As of ISO datetime string: both targets
      results_iso = Analysis.list_targets(as_of: "2023-06-01T12:00:00Z")
      ids_iso = Enum.map(results_iso, & &1.id)
      assert target_a.id in ids_iso
      assert target_b.id in ids_iso

      assert {:error, :invalid_as_of} = Analysis.list_targets(as_of: "invalid-date")
      assert {:error, :invalid_as_of} = Analysis.list_targets(as_of: 123)
    end

    test "list_targets/1 only uses Nikkei 225 memberships" do
      {:ok, nikkei_target} = Analysis.create_target(valid_target_attrs())
      {:ok, topix_target} = Analysis.create_target(valid_target_attrs())

      assert {:ok, _} =
               Analysis.create_membership(nikkei_target, %{
                 index_name: "nikkei_225",
                 effective_from: ~D[2020-01-01]
               })

      assert {:ok, _} =
               Analysis.create_membership(topix_target, %{
                 index_name: "topix",
                 effective_from: ~D[2020-01-01]
               })

      ids = Analysis.list_targets(as_of: ~D[2024-01-01]) |> Enum.map(& &1.id)

      assert nikkei_target.id in ids
      refute topix_target.id in ids
    end
  end
end
