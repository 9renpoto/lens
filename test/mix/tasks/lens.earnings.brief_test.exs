defmodule Mix.Tasks.Lens.Earnings.BriefTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias Mix.Tasks.Lens.Earnings.Brief

  @fixture_path "test/fixtures/earnings/brief_example.json"

  test "prints cited disclosure facts from a fictional record file" do
    output =
      capture_io(fn ->
        Brief.run([@fixture_path])
      end)

    assert output =~ "## 開示ファクト"
    assert output =~ "資源: 人 (people)"
    assert output =~ "事業活動: クラウド基盤の開発・運用"
    assert output =~ "動作: 専任チームの採用を拡大する"
    assert output =~ "状態: 計画 (planned)"
    assert output =~ "出典: 架空工業 2026年3月期 第2四半期 決算短信 p.4「研究開発・人材投資」"
    assert output =~ "> 第2四半期にクラウド基盤チームの採用を前年度比で拡大し、専任体制を立ち上げる計画。"
  end

  test "fails visibly when required evidence is missing or status is invalid" do
    base = @fixture_path |> File.read!() |> Jason.decode!()

    incomplete = write_temp_json(Map.delete(base, "source_locator"))
    invalid_status = write_temp_json(Map.put(base, "status", "rumored"))
    invalid_json = write_temp_raw("{not valid json")

    assert_raise Mix.Error, ~r/source_locator/, fn ->
      Brief.run([incomplete])
    end

    assert_raise Mix.Error, ~r/status.*actual.*planned/, fn ->
      Brief.run([invalid_status])
    end

    assert_raise Mix.Error, ~r/JSON/, fn ->
      Brief.run([invalid_json])
    end

    assert_raise Mix.Error, ~r/Usage: mix lens\.earnings\.brief/, fn ->
      Brief.run([])
    end
  end

  defp write_temp_json(data), do: write_temp_raw(Jason.encode!(data))

  defp write_temp_raw(content) do
    path =
      Path.join(System.tmp_dir!(), "lens_brief_#{System.unique_integer([:positive])}.json")

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
