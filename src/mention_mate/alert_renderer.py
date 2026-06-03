"""Render mention alerts as paired (HTML, plain-text) messages.

Pure: no I/O, no Telethon, no module globals. Callers pass primitives;
the module handles HTML escaping and the link/fallback split.

Two output forms always returned as a tuple:
    html_msg  → sent with parse_mode="HTML"
    plain_msg → fallback if Telegram refuses the HTML parse

The HTML parser is Telegram's, not a browser's — only ``<``, ``>``, ``&``
inside user content need escaping. Plain-text mode does no parsing, so
the plain output uses raw input values verbatim (intentional asymmetry).
"""
import html


def render_alert(
    *,
    sender_name: str,
    chat_title: str,
    message_text: str,
    message_link: str | None,
) -> tuple[str, str]:
    """Return ``(html_msg, plain_msg)`` ready to send via the Bot API.

    ``message_link=None`` produces the basic-group fallback hint
    (Chat / User chats have no Telegram permalink scheme).
    """
    sender_html = html.escape(sender_name)
    chat_html = html.escape(chat_title)
    text_html = html.escape(message_text)

    if message_link:
        link_html = html.escape(message_link, quote=True)
        link_block_html = f'🔗 <a href="{link_html}">Jump to message</a>'
        link_block_plain = f"🔗 {message_link}"
    else:
        link_block_html = (
            f"💡 <i>Open Telegram and check <b>{chat_html}</b> "
            f"to find this message.</i>"
        )
        link_block_plain = (
            f"💡 Open Telegram and check {chat_title} to find this message."
        )

    html_msg = (
        f"🔔 <b>You were mentioned!</b>\n"
        f"👤 <b>From:</b> {sender_html}\n"
        f"🏢 <b>Group:</b> {chat_html}\n\n"
        f"<blockquote>{text_html}</blockquote>\n\n"
        f"{link_block_html}"
    )
    plain_msg = (
        f"🔔 You were mentioned!\n"
        f"👤 From: {sender_name}\n"
        f"🏢 Group: {chat_title}\n\n"
        f"{message_text}\n\n"
        f"{link_block_plain}"
    )
    return html_msg, plain_msg
