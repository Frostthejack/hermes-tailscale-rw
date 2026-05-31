"""Run ~/.hermes/BOOT.md startup checklist on every gateway startup."""
import logging
import threading
from pathlib import Path

logger = logging.getLogger("hooks.boot-md")
BOOT_FILE = Path.home() / ".hermes" / "BOOT.md"
DISCORD_HOME_CHANNEL = "1505057361746722899"


def _build_prompt(content: str) -> str:
    return (
        "You are running a startup boot checklist. Follow the instructions below exactly.\n\n"
        "---\n"
        f"{content}\n"
        "---\n\n"
        "Execute each instruction in order. Use shell commands and tools as needed.\n"
        "If sending a message to a platform, use the send_message tool.\n"
        "If nothing needs attention and there is nothing to report, reply with ONLY: [SILENT]"
    )


def _run_boot_agent(content: str) -> None:
    try:
        from gateway.run import _resolve_gateway_model, _resolve_runtime_agent_kwargs
        from run_agent import AIAgent

        agent = AIAgent(
            model=_resolve_gateway_model(),
            **_resolve_runtime_agent_kwargs(),
            platform="gateway",
            quiet_mode=True,
            skip_context_files=True,
            skip_memory=True,
            max_iterations=20,
        )
        result = agent.run_conversation(_build_prompt(content))
        response = result.get("final_response", "")
        if response and "[SILENT]" not in response:
            logger.info("boot-md report: %s", response[:200])
            try:
                from tools.messaging import send_message
                send_message(target=f"discord:{DISCORD_HOME_CHANNEL}", message=f"📋 **Startup Checklist**\n{response}")
            except Exception as e:
                logger.warning("boot-md: could not send Discord message: %s", e)
        else:
            logger.info("boot-md completed (nothing to report)")
    except Exception as e:
        logger.error("boot-md agent failed: %s", e, exc_info=True)


async def handle(event_type: str, context: dict) -> None:
    if not BOOT_FILE.exists():
        logger.debug("boot-md: no BOOT.md found, skipping")
        return
    content = BOOT_FILE.read_text(encoding="utf-8").strip()
    if not content:
        logger.debug("boot-md: BOOT.md is empty, skipping")
        return
    logger.info("Running BOOT.md (%d chars)", len(content))
    thread = threading.Thread(
        target=_run_boot_agent,
        args=(content,),
        name="boot-md",
        daemon=True,
    )
    thread.start()