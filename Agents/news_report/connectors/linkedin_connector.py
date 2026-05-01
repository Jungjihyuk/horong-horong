class LinkedInConnector:
    def __init__(self, config: dict, max_items: int = 10):
        self.profiles = config.get("profiles", [])
        self.max_items = max_items

    def collect(self) -> list[dict]:
        raise RuntimeError(
            "E_SOURCE_AUTH: LinkedIn 자동 수집은 인증 제한으로 지원되지 않습니다. "
            "수동으로 게시물을 복사하여 yozm_it 소스로 추가하세요."
        )
