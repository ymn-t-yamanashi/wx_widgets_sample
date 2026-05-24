import Config

gpu_flag = System.get_env("ENABLE_GPU") || System.get_env("ENABLE_DNN") || "0"
gpu_enabled = gpu_flag in ["1", "true", "TRUE", "yes", "YES"]

if gpu_enabled do
  config :ortex, Ortex.Native, features: [:cuda]
end
