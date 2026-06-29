from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    mongodb_uri: str
    database_name: str = "dhanam_store"
    jwt_secret: str = "dhanam-store-secret-change-in-production"
    jwt_expiry_hours: int = 720
    debug: bool = False
    cors_origins: list[str] = ["*"]

    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False
    )

settings = Settings()

if "change-in-production" in settings.jwt_secret:
    import logging
    logging.getLogger(__name__).warning(
        "JWT_SECRET is still the default — set a strong secret in .env before deploying"
    )

logging.getLogger(__name__).info("Connected to MongoDB: %s...", settings.mongodb_uri[:20])