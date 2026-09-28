"""Regenerate synthetic PDFs with ReportLab; no publisher material is used."""
from pathlib import Path

from PIL import Image
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader


root = Path(__file__).resolve().parent
pdfmetrics.registerFont(UnicodeCIDFont("HeiseiKakuGo-W5"))
text = canvas.Canvas(str(root / "earnings-text.pdf"), invariant=1)
text.setFont("HeiseiKakuGo-W5", 14)
text.drawString(72, 750, "決算短信")
text.drawString(72, 710, "売上高は１２３億円です。")
text.drawString(72, 670, "営業利益は前年同期比で増加しました。")
text.showPage()
text.save()

image = canvas.Canvas(str(root / "earnings-image.pdf"), invariant=1)
image.drawImage(ImageReader(Image.new("RGB", (100, 100), "navy")), 72, 650, 100, 100)
image.showPage()
image.save()
