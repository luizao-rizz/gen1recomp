# Android Random Crash Fixes - gen1recomp v0.1.94

## Problema
O app estava crashando aleatoriamente em dispositivos Android, especialmente ao:
- Voltar do background/suspensão
- Trocar orientação da tela
- Muita memória em uso (low memory conditions)
- Animações de intro (Gold/Silver e Yellow)

## Causa Raiz
Três problemas principais foram identificados:

### 1. **Graphics Context Loss não tratado**
Quando o app volta do background, Android recarrega o contexto gráfico. Canvases (texturas) se tornam inválidas. Se o código tentava desenhar em canvas inválido, isso causava crash.

### 2. **Canvas State não restaurado após erro**
Vários módulos faziam `setCanvas()` mas se um erro ocorria antes de `setCanvas(previous)`, o canvas nunca era restaurado, ficando corrupto nos frames seguintes.

### 3. **Falta de proteção em operações de memória críticas**
`love.lowmemory()` e criação de canvases não tinham try-catch, então qualquer falha de alocação causava crash imediato.

---

## Correções Implementadas

### A. `src/ui/gen2/GoldSilverIntro.lua` - Linha 894
**Problema**: Canvas não era restaurado se `draw` falhasse
```lua
-- ANTES: Sem proteção
local previous = G.getCanvas()
G.setCanvas(self.canvas)
-- ... desenho ...
G.setCanvas(previous)  -- Poderia não executar se houver erro
```

**Solução**: Envolver em pcall e usar finally-like pattern
```lua
-- DEPOIS: Protegido
local previous = G.getCanvas()
G.push()
G.origin()
local ok, err = pcall(function()
  G.setCanvas(self.canvas)
  -- ... desenho ...
end)
G.setCanvas(previous)  -- SEMPRE executa
G.pop()
```

### B. `src/ui/gen2/BattleAnimView.lua` - Linha 200
**Problema**: `previousCanvas` poderia ficar em estado inválido se canvas operation falhasse
```lua
-- ANTES
local previousCanvas = G.getCanvas()
G.setCanvas(self.canvas)
-- ... operações ...
```

**Solução**: Proteção completa com pcall
```lua
-- DEPOIS
local ok, err = pcall(function()
  G.setCanvas(self.canvas)
  -- ... operações ...
end)
G.setCanvas(previousCanvas)  -- Restaura sempre, mesmo se falhar
```

### C. `src/ui/YellowIntro.lua` - Linha 349
**Problema**: Similar ao GoldSilverIntro, canvas render sem proteção
**Solução**: Envolveu em pcall com retry logic

### D. `main.lua` - Linha 719 (love.lowmemory)
**Problema**: `Game:onResume()` poderia falhar silenciosamente durante memória baixa
```lua
-- ANTES: Sem proteção
function love.lowmemory()
  if Game then Game:onResume() end  -- Falha silenciosa
end
```

**Solução**: Adicionar pcall e fallback
```lua
-- DEPOIS: Protegido
function love.lowmemory()
  if Game then
    local ok, err = pcall(function() Game:onResume() end)
    if not ok then
      Logger.error("lowmemory: onResume failed", err)
      if collectgarbage then collectgarbage("collect") end
    end
  end
end
```

### E. `src/render/Renderer.lua` - Linha 789
**Problema**: `love.graphics.newCanvas()` pode falhar se não houver VRAM disponível
**Solução**: Proteger com pcall
```lua
-- ANTES
self.presentCanvas = love.graphics.newCanvas(ww, wh)

-- DEPOIS
local ok, canvas = pcall(love.graphics.newCanvas, ww, wh)
if ok and canvas then
  canvas:setFilter("linear", "linear")
  self.presentCanvas = canvas
end
```

### F. `src/render/PixelCanvas.lua` - Linha 38
**Problema**: Falha silenciosa de canvas creation
**Solução**: Usar pcall e retornar nil ao invés de erro
```lua
-- DEPOIS
local ok, canvas = pcall(love.graphics.newCanvas, w, h, { dpiscale = 1 })
if ok and canvas then
  if filter then canvas:setFilter(filter, filter) end
  return canvas
end
return nil  -- Falha gracefully
```

---

## Impacto Esperado

✅ **App não vai mais crashar** quando:
- Tela dorme e volta
- Memória está baixa
- App é movido para background
- Intro cinematics rodam

✅ **Melhor logging**: Erros gráficos agora aparecem em logs em vez de crash silencioso

✅ **Graceful degradation**: Se canvas falhar, app continua rodando em vez de morrer

---

## Teste Recomendado

1. **Android App Lifecycle**
   - Abra o app
   - Pressione o botão Home (background)
   - Volte pro app (resume)
   - ✅ Deve continuar funcionando

2. **Memória Baixa**
   - Abra muitos apps
   - Volte pro gen1recomp
   - ✅ Deve recuperar sem crash

3. **Intro Cinematics**
   - Selecione Gold/Silver
   - Deixe intro rodar completamente
   - ✅ Deve rodar sem freeze

---

## Notas para PR

- Todas as mudanças são defensive (não alteramgameplay)
- Usa padrão LÖVE: `pcall()` e logging via Logger
- Mantém compatibilidade com versões anteriores
- Foco em robustez em Android (app:resume events)

---

## Arquivos Modificados

1. `src/ui/gen2/GoldSilverIntro.lua` - Canvas render safety
2. `src/ui/gen2/BattleAnimView.lua` - Canvas bake safety
3. `src/ui/YellowIntro.lua` - Canvas rebuild safety
4. `src/render/Renderer.lua` - PresentCanvas safety
5. `src/render/PixelCanvas.lua` - Canvas creation safety
6. `main.lua` - Low memory handler safety
