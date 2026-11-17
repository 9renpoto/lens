defmodule Lens.AnalysisTest do
  use Lens.DataCase, async: true

  alias Lens.Analysis
  alias Lens.Analysis.Target
  alias Lens.Repo

  defp valid_target_attrs(custom \\ %{}) do
    Map.merge(
      %{
        security_code: "CODE-#{System.unique_integer([:positive])}",
        market: "Fictional Exchange",
        display_name: "Example Components",
        sector: "Transportation Equipment",
        tags: ["automotive", "large-cap"],
        source_reference: "Synthetic issuer profile",
        verified_at: ~U[2024-01-15 10:00:00Z]
      },
      custom
    )
  end

  test "the current database schema contains the target registry without index membership" do
    assert %{rows: [[target_table, nil]]} =
             Repo.query!(
               "SELECT to_regclass('analysis_targets')::text, to_regclass('analysis_memberships')"
             )

    assert target_table == "analysis_targets"
  end

  describe "targets" do
    test "create_target/1 with valid attributes creates a target preserving text security code" do
      attrs = valid_target_attrs(%{security_code: "001-FICT"})
      assert {:ok, target} = Analysis.create_target(attrs)

      assert target.security_code == "001-FICT"
      assert target.market == "Fictional Exchange"
      assert target.display_name == "Example Components"
      assert target.sector == "Transportation Equipment"
      assert target.tags == ["automotive", "large-cap"]
      assert target.active == true
      assert target.source_reference == "Synthetic issuer profile"

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

    test "target string limits count Unicode codepoints like PostgreSQL and OpenAPI" do
      decomposed_fields = [
        {:security_code, String.duplicate("e\u0301", 26)},
        {:market, String.duplicate("e\u0301", 51)},
        {:display_name, String.duplicate("e\u0301", 128)},
        {:sector, String.duplicate("e\u0301", 51)},
        {:source_reference, String.duplicate("e\u0301", 501)},
        {:tags, [String.duplicate("e\u0301", 26)]}
      ]

      for {field, value} <- decomposed_fields do
        changeset = Target.changeset(%Target{}, valid_target_attrs(%{field => value}))

        refute changeset.valid?, "expected #{field} over the codepoint limit to be invalid"
        assert Map.has_key?(errors_on(changeset), field)
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
end
