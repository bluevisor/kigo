"""Fuzzy matching in the spirit of Spotlight/Raycast: exact > prefix >
word-start > acronym > substring > subsequence. A port of src/Fuzzy.cpp, so
every Kigo ranks the same way. Works on UTF-8 bytes like the original."""


def _alpha(c):
    return 65 <= c <= 90 or 97 <= c <= 122


def _digit(c):
    return 48 <= c <= 57


def _alnum(c):
    return _alpha(c) or _digit(c)


def _boundary(text, i):
    if i == 0:
        return True
    prev, cur = text[i - 1], text[i]
    if not _alnum(prev) and prev < 0x80:
        return True
    # camelCase: "WebPositive" has a boundary at 'P'.
    if 97 <= prev <= 122 and 65 <= cur <= 90:
        return True
    # "Haiku3D": letters to digits.
    if _alpha(prev) and _digit(cur):
        return True
    return False


def _lower(data):
    return bytes(c + 32 if 65 <= c <= 90 else c for c in data)


def _score_word(query, text):
    t, q = _lower(text), _lower(query)
    if not q or len(q) > len(t):
        return 0.0
    if t == q:
        return 1000.0
    if t.startswith(q):
        return 900 - (len(t) - len(q)) * 0.5

    # A later word starting with the query: "pos" in "WebPositive".
    for i in range(1, len(t) - len(q) + 1):
        if _boundary(text, i) and t.startswith(q, i):
            return 800.0 - i

    # Acronym: "vsc" -> "Visual Studio Code".
    if len(q) >= 2:
        initials = bytes(t[i] for i in range(len(t)) if _boundary(text, i) and _alnum(t[i]))
        if len(initials) >= len(q) and initials.startswith(q):
            return 750 - (len(initials) - len(q)) * 2.0

    found = t.find(q)
    if found >= 0:
        return 600 - found * 2.0

    # Subsequence with a penalty for each gap and a bonus for boundaries.
    score, qi, last = 400.0, 0, -1
    for i in range(len(t)):
        if qi >= len(q):
            break
        if t[i] != q[qi]:
            continue
        if last >= 0 and i != last + 1:
            score -= 6 + (i - last - 1)
        elif last < 0:
            score -= i * 2
        if _boundary(text, i):
            score += 8
        last = i
        qi += 1
    if qi < len(q):
        return 0.0
    return max(score, 50.0)


def fuzzy_score(query, text):
    """0 when `query` doesn't match `text`, otherwise a score where higher is
    better (exact match = 1000). Case-insensitive; every space-separated word
    of the query must match."""
    if not query or not text:
        return 0.0
    q, t = query.encode(), text.encode()
    if b" " not in q:
        return _score_word(q, t)

    # A multi-word query matching the whole text as a phrase wins.
    phrase = _score_word(q, t)
    if phrase >= 600:
        return phrase

    total, count = 0.0, 0
    for word in q.split(b" "):
        if not word:
            continue
        score = _score_word(word, t)
        if score <= 0:
            return 0.0
        total += score
        count += 1
    return total / count * 0.9 if count else 0.0
