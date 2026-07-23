"""Settings for the JARVIS Mobile Bridge, loaded from environment / .env.

Required in production:
  WEBUI_BASE_URL           http://127.0.0.1:8787
  WEBUI_PASSWORD           the HERMES_WEBUI_PASSWORD set on hermes-webui
  MOBILE_TOKEN             long random hex; passed to the iOS app

Optional in v1 (used in v1.1/APNs):
  APNS_TEAM_ID, APNS_KEY_ID, APNS_KEY_PATH, APNS_TOPIC, APNS_USE_SANDBOX
"""

from __future__ import annotations

from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # hermes-webui
    webui_base_url: str = Field(default="http://127.0.0.1:8787")
    webui_password: SecretStr = Field(default=SecretStr(""))
    webui_login_retries: int = Field(default=3)

    # Bearer auth for the phone
    mobile_token: SecretStr = Field(default=SecretStr(""))

    # The upstream Hermes runtime owns the actual profile and personality
    # instructions. The bridge selects these defaults when a request omits
    # them explicitly.
    jarvis_profile: str = Field(default="jarvis")
    jarvis_personality: str = Field(default="jarvis")

    # Runs registry / SQLite
    runs_db_path: str = Field(default="./runs.sqlite")

    # Bridge bind
    bridge_host: str = Field(default="127.0.0.1")
    bridge_port: int = Field(default=8080)

    # SSE behaviour
    sse_proxy_write_deadline_seconds: float = Field(default=120.0)

    # APNs (v1.1)
    apns_team_id: str = Field(default="")
    apns_key_id: str = Field(default="")
    apns_key_path: str = Field(default="")
    apns_topic: str = Field(default="com.hermes.mobile")
    apns_use_sandbox: bool = Field(default=True)

    @property
    def apns_configured(self) -> bool:
        return (
            all([self.apns_team_id, self.apns_key_id, self.apns_key_path])
            and Path(self.apns_key_path).exists()
        )


_settings: Settings | None = None


def get_settings() -> Settings:
    """Lazy singleton (cached after first load)."""
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
