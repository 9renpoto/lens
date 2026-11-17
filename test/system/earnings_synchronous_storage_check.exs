# Run with an isolated disposable PostgreSQL database and RustFS bucket namespace.
Application.ensure_all_started(:ecto_sql)
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:req)
config = Application.fetch_env!(:lens, Lens.Repo)
Application.put_env(:lens, Lens.Repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
{:ok, repo} = Lens.Repo.start_link()
Process.unlink(repo)
Lens.Release.prepare()
ExUnit.start(seed: 0)

defmodule Lens.SynchronousStorageCheck do
  use ExUnit.Case, async: false
  alias Lens.Earnings.{Acquisition, HTTPCheck, HTTPHistory, Original, RustFS}
  alias Lens.Repo

  setup_all do
    bucket = "lens-save-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    {:ok, client} =
      RustFS.new(
        endpoint: System.fetch_env!("LENS_RUSTFS_ENDPOINT"),
        bucket: bucket,
        access_key_id: System.fetch_env!("LENS_RUSTFS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("LENS_RUSTFS_SECRET_ACCESS_KEY")
      )

    assert {:ok, %{status: 200}} = Req.put(client.request, url: client.endpoint <> "/" <> bucket)
    %{client: client}
  end

  setup do
    id = Ecto.UUID.generate()

    attrs = %{
      check_id: id,
      issuer_code: "issuer-alpha",
      kind: :pdf,
      url: "https://publisher.invalid/" <> id,
      checked_at: DateTime.utc_now(),
      metadata: %{},
      result: %{
        outcome: :success,
        final_url: "https://publisher.invalid/" <> id,
        bytes: "%PDF-" <> id,
        http_status: 200,
        requests: 1,
        retryable: false,
        headers: %{}
      }
    }

    %{attrs: attrs, bytes: attrs.result.bytes}
  end

  test "repeated observations preserve history and reuse verified originals", c do
    assert {:ok, first} = HTTPHistory.store(c.attrs, c.client)
    first_acquisition = Repo.get!(Acquisition, first.acquisition_id)
    assert Repo.get!(Original, first_acquisition.original_id).endpoint == c.client.endpoint

    assert Lens.Earnings.original_bytes(first_acquisition.original_id, rustfs: c.client) ==
             {:ok, c.bytes}

    next = %{c.attrs | check_id: Ecto.UUID.generate()}
    assert {:ok, second} = HTTPHistory.store(next, c.client)
    second_acquisition = Repo.get!(Acquisition, second.acquisition_id)
    assert first.id != second.id
    assert first.acquisition_id != second.acquisition_id
    assert second_acquisition.original_id == first_acquisition.original_id
    assert Repo.get!(HTTPCheck, first.id) == first
    assert Repo.get!(Acquisition, first_acquisition.id) == first_acquisition
  end

  test "failed save is explicit and a new observation can save without a recovery queue", c do
    bad = %{
      c.client
      | bucket: "absent-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    }

    assert {:storage_failed, "not_found"} = HTTPHistory.store(c.attrs, bad)
    failed = Repo.get_by!(Acquisition, acquisition_id: "http:" <> c.attrs.check_id)
    assert failed.status == "failed"
    assert failed.original_id == nil
    assert Repo.get_by(HTTPCheck, check_id: c.attrs.check_id) == nil
    next = %{c.attrs | check_id: Ecto.UUID.generate()}
    assert {:ok, check} = HTTPHistory.store(next, c.client)
    successful = Repo.get!(Acquisition, check.acquisition_id)

    assert Lens.Earnings.original_bytes(successful.original_id, rustfs: c.client) ==
             {:ok, c.bytes}
  end

  test "an already written object is verified and reused without recovery state", c do
    assert {:ok, reference} = RustFS.put(c.client, c.bytes)
    assert {:ok, check} = HTTPHistory.store(c.attrs, c.client)
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert Repo.get!(Original, acquisition.original_id).sha256 == reference.sha256

    assert Lens.Earnings.original_bytes(acquisition.original_id, rustfs: c.client) ==
             {:ok, c.bytes}
  end
end
