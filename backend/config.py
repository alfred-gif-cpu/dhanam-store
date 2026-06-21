from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    mongodb_uri: str
    database_name: str = "dhanam_store"
    jwt_secret: str = "dhanam-store-secret-change-in-production"
    jwt_expiry_hours: int = 720

    model_config = SettingsConfigDict(
        env_file=".env",
        case_sensitive=False
    )

settings = Settings()

print("Mongo URI:", settings.mongodb_uri[:20])