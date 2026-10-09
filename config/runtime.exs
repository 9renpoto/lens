import Config

rustfs_values = [
  endpoint: System.get_env("LENS_RUSTFS_ENDPOINT"),
  bucket: System.get_env("LENS_RUSTFS_BUCKET"),
  access_key_id: System.get_env("LENS_RUSTFS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("LENS_RUSTFS_SECRET_ACCESS_KEY")
]

rustfs_region = System.get_env("LENS_RUSTFS_REGION")
rustfs_timeout = System.get_env("LENS_RUSTFS_TIMEOUT_MS")

if Enum.any?(rustfs_values, fn {_, value} -> not is_nil(value) end) or
     not is_nil(rustfs_region) or not is_nil(rustfs_timeout) do
  timeout = Integer.parse(rustfs_timeout || "30000")

  unless Enum.all?(rustfs_values, fn {_, value} -> is_binary(value) and value != "" end) and
           match?({milliseconds, ""} when milliseconds in 1..30_000, timeout) do
    raise ArgumentError, "invalid RustFS configuration"
  end

  {timeout_ms, ""} = timeout

  config :lens,
         Lens.Earnings.RustFS,
         rustfs_values ++ [region: rustfs_region || "us-east-1", timeout_ms: timeout_ms]
end

case System.get_env("LENS_STORAGE_RECOVERY_ENABLED") do
  nil -> :ok
  "true" -> config :lens, Lens.Earnings.StorageRecovery, enabled: true
  "false" -> config :lens, Lens.Earnings.StorageRecovery, enabled: false
  _ -> raise ArgumentError, "invalid storage recovery configuration"
end

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")
  secret_key_base = System.get_env("SECRET_KEY_BASE")
  host = System.get_env("PHX_HOST", "localhost")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :lens, Lens.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :lens, LensWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port]

  if secret_key_base do
    config :lens, LensWeb.Endpoint, secret_key_base: secret_key_base
  end
end
