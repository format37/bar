import os
import time
import json
from pathlib import Path
import sys
from openai import OpenAI

# Configuration
# Load OpenAI key from environment
client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY") or os.getenv("OPENAI_KEY")
)
if not client.api_key:
    raise SystemExit("OpenAI API key not found in environment variable 'OPENAI_API_KEY' or 'OPENAI_KEY'.")

# Model name to use for chat completion
MODEL_NAME = "gpt-4.1-nano-2025-04-14"

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
PROMPT_PATH = SCRIPT_DIR / "prompt.txt"
GAME_STATE_PATH = SCRIPT_DIR / "game_state.json"
RECOMMENDATION_PATH = SCRIPT_DIR / "recommendation.json"

# Polling interval (seconds) when waiting for a new game state
POLL_INTERVAL = 1.0

# Helper functions
def load_system_prompt() -> str:
    """Load system prompt from PROMPT_PATH. Exit if the file is missing."""
    if not PROMPT_PATH.exists():
        raise SystemExit(f"System prompt file '{PROMPT_PATH}' not found.")
    return PROMPT_PATH.read_text(encoding="utf-8")

def safe_load_json(path: Path):
    """Safely load JSON from a file. Returns None on failure."""
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def write_recommendation(game_time: float, recommendation_time: float, recommendation: str):
    """Write recommendation to RECOMMENDATION_PATH in the required schema."""
    data = {
        "game_time": round(game_time, 1),
        "recommendation_time": round(recommendation_time, 1),
        "recommendation": recommendation.strip(),
    }
    # Ensure directory exists
    RECOMMENDATION_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = RECOMMENDATION_PATH.with_suffix(".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(data, f)
    # Atomic rename
    tmp_path.replace(RECOMMENDATION_PATH)

# Main loop
def main() -> None:
    system_prompt = load_system_prompt()
    last_game_time: float | None = None

    print("[llm_recommendation] Started. Waiting for game_state updates...")
    while True:
        if not GAME_STATE_PATH.exists():
            time.sleep(POLL_INTERVAL)
            continue

        start_wall = time.time()
        state_data = safe_load_json(GAME_STATE_PATH)
        if not state_data:
            # Failed to parse; try again shortly
            time.sleep(POLL_INTERVAL)
            continue

        game_time = state_data.get("game_time")
        if game_time is None:
            # Malformed data; skip until corrected
            time.sleep(POLL_INTERVAL)
            continue

        # Skip if we've already handled this game_time
        if last_game_time is not None and game_time == last_game_time:
            time.sleep(POLL_INTERVAL)
            continue

        # Build messages for a fresh chat completion request
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(state_data)},
        ]

        try:
            response = client.chat.completions.create(
                model=MODEL_NAME,
                messages=messages,
                temperature=0.7,
            )
            assistant_content = response.choices[0].message.content.strip()
        except Exception as exc:
            print(f"[llm_recommendation] OpenAI API call failed: {exc}")
            time.sleep(POLL_INTERVAL)
            continue

        elapsed_wall = time.time() - start_wall  # seconds spent from reading to generation
        recommendation_time = game_time + elapsed_wall

        write_recommendation(game_time, recommendation_time, assistant_content)
        print(
            f"[llm_recommendation] Generated recommendation for game_time={game_time:.1f} -> '{assistant_content[:60]}...'."
        )

        last_game_time = game_time
        # Small sleep before next iteration to avoid tight looping
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()