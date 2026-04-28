"""
brain/embeddings.py — Local embedding wrapper using sentence-transformers.

Model: all-MiniLM-L6-v2 (384 dimensions, ~80MB)
Runs entirely on-device — no external API calls, no API key needed.
"""

import logging

logger = logging.getLogger(__name__)

EMBEDDING_MODEL = "all-MiniLM-L6-v2"
EMBEDDING_DIM = 384

_model = None


def _get_model():
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        logger.info("Loading embedding model: %s", EMBEDDING_MODEL)
        _model = SentenceTransformer(EMBEDDING_MODEL)
        logger.info("Embedding model loaded")
    return _model


def embed(text: str) -> list[float]:
    """Return a 384-dim embedding for the given text. Runs locally."""
    if not text:
        raise ValueError("embed() called with empty text")
    model = _get_model()
    vec = model.encode(text).tolist()
    if len(vec) != EMBEDDING_DIM:
        raise RuntimeError(
            f"Embedding dim mismatch: got {len(vec)}, expected {EMBEDDING_DIM}"
        )
    return vec
