import html.parser

class TagValidator(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack = []
        self.void_tags = {'meta', 'link', 'img', 'br', 'hr', 'input', 'path', 'line', 'polyline', 'rect', 'circle', 'polygon'}
        self.errors = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() not in self.void_tags:
            self.stack.append((tag.lower(), self.getpos()))

    def handle_endtag(self, tag):
        t = tag.lower()
        if t in self.void_tags:
            return
        if not self.stack:
            self.errors.append(f"Cierre inesperado </{t}> en linea {self.getpos()[0]}")
            return
        last, pos = self.stack.pop()
        if last != t:
            self.errors.append(f"Desajuste: se esperaba </{last}> (abierto en linea {pos[0]}), pero se encontro </{t}> en linea {self.getpos()[0]}")

with open(r'c:\EGalli\Carniceria_Gorina\Tablero_Carniceria.html', 'r', encoding='utf-8') as f:
    code = f.read()

v = TagValidator()
v.feed(code)
if v.errors:
    for e in v.errors[:10]:
        print("ERROR:", e)
else:
    print("HTML perfectamente balanceado! Sin errores de etiquetas.")
if v.stack:
    print("Etiquetas sin cerrar:", v.stack)
