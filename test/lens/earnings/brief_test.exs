defmodule Lens.Earnings.BriefTest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.Brief

  @fixture_path "test/fixtures/earnings/brief_example.json"

  test "loads a fictional disclosure record and renders facts with exact excerpt and citation" do
    assert {:ok, brief} = Brief.load_file(@fixture_path)
    assert brief.resource == "people"
    assert brief.status == "planned"

    rendered = Brief.render_facts(brief)

    assert rendered =~ "## 開示ファクト"
    assert rendered =~ "資源: 人 (people)"
    assert rendered =~ "事業活動: クラウド基盤の開発・運用"
    assert rendered =~ "動作: 専任チームの採用を拡大する"
    assert rendered =~ "状態: 計画 (planned)"
    assert rendered =~ "出典: 架空工業 2026年3月期 第2四半期 決算短信 p.4「研究開発・人材投資」"
    assert rendered =~ "> 第2四半期にクラウド基盤チームの採用を前年度比で拡大し、専任体制を立ち上げる計画。"
  end

  test "renders all supported resources and actual status" do
    for {resource, label} <- [
          {"people", "人 (people)"},
          {"capital", "資金 (capital)"},
          {"equipment", "設備 (equipment)"}
        ] do
      attrs = %{
        "excerpt" => "架空の工場へ新規設備を導入した。",
        "resource" => resource,
        "activity" => "製造ライン自動化",
        "action" => "新規設備を導入した",
        "status" => "actual",
        "source_locator" => "架空製造 2026年3月期 通期 決算短信 p.2"
      }

      assert {:ok, brief} = Brief.new(attrs)
      rendered = Brief.render_facts(brief)
      assert rendered =~ "資源: #{label}"
      assert rendered =~ "状態: 実施済み (actual)"
    end
  end

  test "rejects missing or blank required fields with actionable reasons" do
    base = @fixture_path |> File.read!() |> Jason.decode!()

    for field <- ~w(excerpt resource activity action status source_locator) do
      assert {:error, {:missing_field, ^field}} = Brief.new(Map.delete(base, field))
      assert {:error, {:missing_field, ^field}} = Brief.new(Map.put(base, field, "   "))
      assert {:error, {:missing_field, ^field}} = Brief.new(Map.put(base, field, nil))
    end
  end

  test "rejects invalid resource, invalid status, unknown keys, and non-object inputs" do
    base = @fixture_path |> File.read!() |> Jason.decode!()

    assert {:error, {:invalid_resource, "brand"}} =
             Brief.new(Map.put(base, "resource", "brand"))

    assert {:error, {:invalid_status, "rumored"}} =
             Brief.new(Map.put(base, "status", "rumored"))

    assert {:error, {:unknown_fields, ["extra"]}} =
             Brief.new(Map.put(base, "extra", "unexpected"))

    assert {:error, :invalid_record} = Brief.new(["not", "an", "object"])
  end
end
