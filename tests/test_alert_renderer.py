"""Tests for alert_renderer.

Expected output strings are captured inline as ``_EXPECTED_*`` constants
(no separate fixture directory) — the values lock the renderer to
byte-identical output for the canonical happy-path inputs.

Tests cover:
- Two happy-path comparisons (supergroup-with-link, basic-group-without-link).
- HTML escape for sender_name, chat_title (in fallback), message_text.
- href attribute escape for an adversarial message_link.
- Plain-text intentionally uses raw values (Telegram doesn't parse).
"""
from mention_mate.alert_renderer import render_alert


_EXPECTED_HTML_SUPER = (
    "🔔 <b>You were mentioned!</b>\n"
    "👤 <b>From:</b> Hoang\n"
    "🏢 <b>Group:</b> Backend Team\n\n"
    "<blockquote>hey @duong check this please</blockquote>\n\n"
    '🔗 <a href="https://t.me/c/12345/99">Jump to message</a>'
)
_EXPECTED_PLAIN_SUPER = (
    "🔔 You were mentioned!\n"
    "👤 From: Hoang\n"
    "🏢 Group: Backend Team\n\n"
    "hey @duong check this please\n\n"
    "🔗 https://t.me/c/12345/99"
)
_EXPECTED_HTML_BASIC = (
    "🔔 <b>You were mentioned!</b>\n"
    "👤 <b>From:</b> Hoang\n"
    "🏢 <b>Group:</b> Backend Team\n\n"
    "<blockquote>hey @duong check this please</blockquote>\n\n"
    "💡 <i>Open Telegram and check <b>Backend Team</b> "
    "to find this message.</i>"
)
_EXPECTED_PLAIN_BASIC = (
    "🔔 You were mentioned!\n"
    "👤 From: Hoang\n"
    "🏢 Group: Backend Team\n\n"
    "hey @duong check this please\n\n"
    "💡 Open Telegram and check Backend Team to find this message."
)


def test_supergroup_with_link_matches_expected():
    html_msg, plain_msg = render_alert(
        sender_name="Hoang",
        chat_title="Backend Team",
        message_text="hey @duong check this please",
        message_link="https://t.me/c/12345/99",
    )
    assert html_msg == _EXPECTED_HTML_SUPER
    assert plain_msg == _EXPECTED_PLAIN_SUPER


def test_basic_group_without_link_matches_expected():
    html_msg, plain_msg = render_alert(
        sender_name="Hoang",
        chat_title="Backend Team",
        message_text="hey @duong check this please",
        message_link=None,
    )
    assert html_msg == _EXPECTED_HTML_BASIC
    assert plain_msg == _EXPECTED_PLAIN_BASIC


def test_html_escape_sender_name():
    html_msg, _ = render_alert(
        sender_name="<script>alert(1)</script>",
        chat_title="Group",
        message_text="hi",
        message_link="http://x",
    )
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html_msg
    assert "<script>" not in html_msg


def test_html_escape_chat_title_in_fallback():
    # chat_title appears in BOTH the header line AND the basic-group fallback;
    # both must be escaped.
    html_msg, _ = render_alert(
        sender_name="Hoang",
        chat_title="</b><b>injected",
        message_text="hi",
        message_link=None,
    )
    assert "&lt;/b&gt;&lt;b&gt;injected" in html_msg
    # The only legitimate <b>...</b> wrappers we emit: 3 in the header
    # (title, From, Group) + 1 around the chat title in the fallback = 4.
    # No raw <b> tags from the injected chat title leaked through.
    assert html_msg.count("</b>") == 4
    assert html_msg.count("<b>") == 4


def test_html_escape_message_text():
    html_msg, _ = render_alert(
        sender_name="Hoang",
        chat_title="Group",
        message_text="5 < 10 & 10 > 5",
        message_link="http://x",
    )
    assert "5 &lt; 10 &amp; 10 &gt; 5" in html_msg


def test_link_href_quote_escape():
    # Defence in depth — Telegram username regex would prevent this in practice,
    # but the renderer must escape href content unconditionally.
    html_msg, _ = render_alert(
        sender_name="Hoang",
        chat_title="Group",
        message_text="hi",
        message_link='http://x.com/"><script>',
    )
    # No raw quote/angle-bracket leaks out of the href value.
    assert '"><script>' not in html_msg
    assert '&quot;&gt;&lt;script&gt;' in html_msg


def test_plain_text_uses_raw_strings():
    # Plain-text mode does no parsing in Telegram, so raw content is correct.
    _, plain_msg = render_alert(
        sender_name="<script>",
        chat_title="Group",
        message_text="5 < 10",
        message_link="x",
    )
    assert "<script>" in plain_msg
    assert "5 < 10" in plain_msg
    assert "&lt;" not in plain_msg
