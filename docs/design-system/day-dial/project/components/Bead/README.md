# Bead

One entry on the dial: a disc whose colour names the habit and whose size shows the amount.

**Provide:** the habit's creation index (its colour and repeat style), the entry's quantity, the habit's typical quantity, and whether it is pending.

- Colour: index mod 5 picks `data1`–`data5`. Indices 0–4 are filled, 5–9 are hollow rings (stroke 2.4, radius minus 1.2), 10–14 are dotted rings.
- Size: radius 7.5 × √(quantity ÷ typical), clamped to 5–14.
- Light: add an inner 1.25px rim in `dataNRim`. Dark: add a 6px glow in `dataNGlow`. Draw both always; each is transparent in the other theme.
- Pending: hollow, with a dashed rim (2px, dashes 3.2/2.6) turning every 2 s. On sync the fill grows from the centre over 240 ms.
- Reuse the same bead at 30px in history rows and on the entry sheet.
- Hit target: radius + 6.

**Do not** draw text on a bead, outline it in ink, or use a habit colour for anything that is not a bead, pip, wedge or chart series. A ring bead in light has no rim yet: see the brand book's accessibility table.
