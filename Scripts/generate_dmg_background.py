#!/usr/bin/env python3
"""DMG配布物のFinderウィンドウ背景画像(Resources/dmg-background.png)を生成する。

`Scripts/sign_and_notarize.sh`がDMG作成時にこの画像を背景として設定し、
AppleScriptでアイコン位置をこの画像のレイアウトに合わせて配置する
(アプリアイコン・矢印・/Applicationsエイリアスの位置は`sign_and_notarize.sh`側の
`set position of item ...`と対応させる必要があるため、座標を変えたら両方直すこと)。

Pillowが必要: `python3 -m pip install --user Pillow`
実行: python3 Scripts/generate_dmg_background.py
"""
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 660, 400
# アイコンサイズ96pxを前提にした中心座標。Finderはアイコンの下にファイル名ラベルを
# 描画するため、キャプション文字列(下の`caption`/`note`)とラベルが重ならないよう、
# アイコン中心のYはウィンドウ上寄りにしてある(sign_and_notarize.shの
# `icon size of theViewOptions`と`set position of item`もこの値に合わせること)。
APP_ICON_X, APP_ICON_Y = 165, 130
DEST_ICON_X, DEST_ICON_Y = 495, 130
ARROW_Y = APP_ICON_Y
BACKGROUND_COLOR = (246, 246, 248)
TEXT_COLOR = (60, 60, 64)
ARROW_COLOR = (150, 150, 156)

# ひらがな/カタカナ/常用漢字を含む和文表示には、このサンドボックス環境で確認できた
# フォントの中で唯一AquaKana.ttc(Appleのかな表示用フォールバックフォント)が対応していた。
# 通常のmacOS環境(ヒラギノ角ゴシック等がインストール済み)ではより見栄えの良いフォントに
# 差し替えてよい。
FONT_PATH = "/System/Library/Fonts/AquaKana.ttc"


def draw_arrow(draw: ImageDraw.ImageDraw, x1: int, y: int, x2: int) -> None:
    draw.line([(x1, y), (x2 - 20, y)], fill=ARROW_COLOR, width=3)
    draw.polygon(
        [(x2, y), (x2 - 22, y - 10), (x2 - 22, y + 10)],
        fill=ARROW_COLOR,
    )


def main() -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(img)

    icon_gap = 70
    draw_arrow(draw, APP_ICON_X + icon_gap, ARROW_Y, DEST_ICON_X - icon_gap)

    # アイコンラベル(Finderがアイコン下に描画するファイル名、アイコン中心から
    # およそ+48〜+68pxの帯)を避けるため、キャプションは+140px以降に置く。
    caption_font = ImageFont.truetype(FONT_PATH, 20)
    caption = "アプリを /Applications へドラッグしてください"
    caption_bbox = draw.textbbox((0, 0), caption, font=caption_font)
    caption_w = caption_bbox[2] - caption_bbox[0]
    draw.text(
        ((WIDTH - caption_w) / 2, ARROW_Y + 150),
        caption,
        font=caption_font,
        fill=TEXT_COLOR,
    )

    note_font = ImageFont.truetype(FONT_PATH, 16)
    note = "インストール後は画面右上のメニューバーのアイコンを確認してください"
    note_bbox = draw.textbbox((0, 0), note, font=note_font)
    note_w = note_bbox[2] - note_bbox[0]
    draw.text(
        ((WIDTH - note_w) / 2, HEIGHT - 50),
        note,
        font=note_font,
        fill=TEXT_COLOR,
    )

    out_path = "Resources/dmg-background.png"
    img.save(out_path)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
