# Correções da auditoria — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir os 14 achados da auditoria de 2026-11-18 (segurança, bugs, testes, código morto) sem mudar a interface MCP das ferramentas.

**Architecture:** Mudanças pequenas e locais em `Sources/MCPServer/main.swift` e `InputGuard.swift`. A lógica que precisa de teste vira função livre e pura (`rankElementMatches`, `mergeComposedResults`, `hitPoint`, `pruneResponseFiles`) e é coberta por um novo target XCTest que faz `@testable import` do executável.

**Tech Stack:** Swift 5.9, SwiftPM, XCTest, MCP swift-sdk 0.12.1, MacosUseSDK.

**Spec:** relatório de auditoria nesta conversa (achados 1–14). Cada tarefa cita o número do achado.

## Global Constraints

- Build: `xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift build 2>&1 | tail -5`, depois de **toda** mudança em `Sources/`.
- Testes: `xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift test 2>&1 | tail -20`.
- Teste de ponta a ponta: `python3 scripts/test_mcp.py`. Nunca chamar `mcp__macos-use__*` direto depois de um rebuild.
- Trabalhar num worktree: `WORKTRUNK_WORKTREE_PATH='{{ repo_path }}/.worktree/{{ branch | sanitize }}' wt switch --create fix/audit-findings`. Antes, adicionar `.worktree/` ao `.gitignore`, que hoje não tem essa entrada.
- Commits em inglês, no padrão Conventional Commits, terminando com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Os nomes, os parâmetros e o formato da resposta das ferramentas MCP não mudam.
- `ElementData`/`ResponseData` do SDK não têm `init` público. Nos testes, crie essas instâncias com `JSONDecoder` (os dois tipos são `Codable`). `ActionResult` tem `init` público.

## Review Focus

- `element` sem nenhum match, ou com match exato só numa janela fora da tela → precisa dar erro claro ou clicar no visível, nunca no oculto (Task 7).
- A pasta de saída já existe com dono ou permissão errada → o servidor não pode gravar nela (Task 4).
- O prune roda enquanto outra chamada está gravando → só apaga `.txt`/`.png` mais antigos que o corte (Task 4).
- Modo composto em que o clique falha mas a digitação funciona, ou o contrário → o erro aparece na resposta (Task 6).
- O tap não é criado → o overlay some no `disengage()` e no watchdog (Task 2).

---

### Task 1: Target de testes + remover `unsafeFlags` (achados 9 e 14)

**Files:**
- Rename: `Sources/MCPServer/main.swift` → `Sources/MCPServer/MCPServer.swift`
- Modify: `Package.swift` (remover `swiftSettings`, adicionar `.testTarget`)
- Create: `Tests/MCPServerTests/ResponseFilteringTests.swift`

**Interfaces:**
- Produces: target `MCPServerTests`, com `@testable import mcp_server_macos_use` e `import MacosUseSDK`. Helper de teste `func element(_ json: String) -> ElementData` (decodifica JSON) no mesmo arquivo; as próximas tarefas reutilizam esse helper.

- [ ] **Step 1:** `git mv` do arquivo e apagar a linha `swiftSettings: [.unsafeFlags(["-parse-as-library"])]`. Com `@main` num arquivo que não se chama `main.swift`, a flag não é mais necessária.
- [ ] **Step 2:** Adicionar `.testTarget(name: "MCPServerTests", dependencies: ["mcp-server-macos-use", .product(name: "MacosUseSDK", package: "MacosUseSDK")], path: "Tests/MCPServerTests")`.
- [ ] **Step 3: Escrever os testes**

```swift
func test_findTextForElement_usesChildTextInsideBounds() {
    let row = element(#"{"role":"AXRow","x":0,"y":0,"width":100,"height":20}"#)
    let child = element(#"{"role":"AXStaticText","text":"Inbox","x":5,"y":5,"width":40,"height":10}"#)
    let traversal = response([row, child])
    XCTAssertEqual(findTextForElement(row, in: traversal), "Inbox")
}
func test_isStructuralNoise_keepsRowsWithText() {
    XCTAssertTrue(isStructuralNoise("AXRow", text: nil))
    XCTAssertFalse(isStructuralNoise("AXRow", text: "Inbox"))
    XCTAssertFalse(isStructuralNoise("AXButton", text: nil))
}
func test_buildToolResponse_dropsScrollBarAndCoordinateOnlyChanges() {
    // diff com 1 AXScrollBar adicionado + 1 AXButton "OK" adicionado + 1 modified só com "x"
    // esperado: diff.added.map(\.text) == ["OK"], diff.modified.isEmpty
}
```

`response(_:)` decodifica `{"app_name":"T","elements":[...],"stats":{},"processing_time_seconds":"0"}`. Se `Statistics` exigir chaves, mande todas com 0.

- [ ] **Step 4:** Rodar o build e depois `swift test`. Esperado: 3 testes passam. Se o link falhar por causa do `main` do executável, confirme que `swift-tools-version` é 5.9 (o SwiftPM renomeia o símbolo para testes a partir da 5.5).
- [ ] **Step 5:** Commit `test: add unit test target and drop parse-as-library flag`.

---

### Task 2: Overlay preso quando o tap falha (achado 1)

**Files:**
- Modify: `Sources/MCPServer/InputGuard.swift:139-145` (bloco `guard let tap ... else`)

- [ ] **Step 1:** No `else` do `CGEvent.tapCreate`, apagar `lock.lock(); _engaged = false; lock.unlock()` e manter o `fputs` de erro e o `return`. Comentário de uma linha: `// keep _engaged so disengage() still removes the overlay`.
- [ ] **Step 2:** Rodar o build.
- [ ] **Step 3: Verificação manual:** trocar temporariamente `guard let tap = CGEvent.tapCreate(...)` por `guard let tap = Optional<CFMachPort>.none`, rodar `python3 scripts/test_mcp.py` e confirmar que o overlay aparece e some ao fim de cada chamada. Desfazer a troca.
- [ ] **Step 4:** Commit `fix: hide input guard overlay when event tap creation fails`.

---

### Task 3: Tirar dados sensíveis dos logs (achado 2)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`, nos logs do handler `CallTool`
- Modify: `Sources/MCPServer/InputGuard.swift`, no bloco "Log every hardware event"

- [ ] **Step 1:** Trocar o log `arguments received (raw MCP)` por `argument keys: \(params.arguments?.keys.sorted() ?? [])`.
- [ ] **Step 2:** Apagar os logs `constructed PrimaryAction: \(primaryAction)` e `composed — additional action \(additionalAction) done` (os dois imprimem `.type(text:)`). Trocar o segundo por `composed — additional action done`.
- [ ] **Step 3:** Nos logs de `click_and_traverse` que imprimem `elementSearch`/`match.text`, deixar o texto como está: ele vem de rótulos da UI, não do que o usuário digitou.
- [ ] **Step 4:** Apagar o bloco `if type == .keyDown || type == .keyUp { ... keyCode ... }` do `inputGuardCallback`.
- [ ] **Step 5: Verificar:** `grep -nE 'debugDescription|\\\(primaryAction\)|\\\(additionalAction\)|keyCode=' Sources -r` não retorna nada. Rodar o build.
- [ ] **Step 6:** Commit `fix: stop logging typed text and hardware keystrokes`.

---

### Task 4: Pasta de saída por usuário + limpeza (achados 3, 8 e 12)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift` (bloco "Write flat text to file", ~linha 1961, e `main()`)
- Modify: `CLAUDE.md`, `llms.txt` (trocar `/tmp/macos-use/` por "a pasta indicada em `file:`", que fica em `$TMPDIR/macos-use/`)
- Test: `Tests/MCPServerTests/OutputDirectoryTests.swift`

**Interfaces:**
- Produces:
  - `let responseOutputDir: String`, global, `= (NSTemporaryDirectory() as NSString).appendingPathComponent("macos-use")`
  - `func prepareOutputDirectory(_ path: String) throws`: cria a pasta com `[.posixPermissions: 0o700]`; se ela já existe, falha quando o dono não é `getuid()` e força 0o700.
  - `func pruneResponseFiles(in dir: String, olderThan age: TimeInterval, now: Date = Date())`: apaga só `.txt`/`.png` com `modificationDate < now - age`.

- [ ] **Step 1: Testes**

```swift
func test_prune_removesOnlyOldResponseFiles() throws {
    // tmp dir com old.txt e old.png (mtime = now-2d), new.txt (mtime = now), keep.json (mtime = now-2d)
    pruneResponseFiles(in: dir, olderThan: 86_400, now: now)
    XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir)), ["new.txt", "keep.json"])
}
func test_prepareOutputDirectory_setsOwnerOnlyPermissions() throws {
    try prepareOutputDirectory(dir)
    let perms = try FileManager.default.attributesOfItem(atPath: dir)[.posixPermissions] as? Int
    XCTAssertEqual(perms, 0o700)
}
```

- [ ] **Step 2:** Rodar `swift test` e ver os testes falharem (as funções ainda não existem).
- [ ] **Step 3:** Implementar as duas funções. Em `main()`, antes de `setupAndStartServer()`: `try? prepareOutputDirectory(responseOutputDir)` e `pruneResponseFiles(in: responseOutputDir, olderThan: 86_400)`.
- [ ] **Step 4:** No handler, trocar `let outputDir = "/tmp/macos-use"` e o `createDirectory` por `try prepareOutputDirectory(responseOutputDir)`. Se der erro, o chamador recebe `isError` pelo `catch` genérico, que é melhor do que gravar numa pasta de outro usuário.
- [ ] **Step 5:** Achado 12, nas mesmas linhas: trocar `resultTextString.count` por `resultTextString.utf8.count` no log e no `fileSize:`.
- [ ] **Step 6:** Rodar o build, o `swift test` e o `python3 scripts/test_mcp.py`. Conferir que o `file:` do resumo aponta para `/var/folders/.../macos-use/` e que `ls -ld` mostra `drwx------`.
- [ ] **Step 7:** Commit `fix: write responses to a private per-user directory and prune old files`.

---

### Task 5: Detectar troca de app antes de devolver o foco (achado 4)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`, entre "Restore cursor position" e "Detect cross-app handoff"

- [ ] **Step 1:** Antes de "Restore cursor position", guardar `let frontmostAfterAction = NSWorkspace.shared.frontmostApplication`.
- [ ] **Step 2:** No bloco de troca de app, usar `frontmostAfterAction` em vez de chamar `NSWorkspace.shared.frontmostApplication` de novo (as duas chamadas, PID e nome). O bloco pode continuar onde está, porque agora ele lê o valor capturado antes da restauração. A traversal do novo app continua depois do `buildToolResponse`.
- [ ] **Step 3:** Rodar o build.
- [ ] **Step 4: Verificação manual** com `python3 scripts/test_mcp.py`: num clique simples (por exemplo, no Calculator), o resumo **não** tem `app_switch:`. Num clique que abre outro app (um link num app de chat que abre o navegador), o resumo tem `app_switch:` com o navegador.
- [ ] **Step 5:** Commit `fix: capture frontmost app before restoring focus`.

---

### Task 6: Erros no modo composto + troca de app (achado 5)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`, bloco "Composed multi-action path"
- Test: `Tests/MCPServerTests/ComposedResultTests.swift`

**Interfaces:**
- Consumes: Task 5 (`frontmostAfterAction`).
- Produces: `func mergeComposedResults(primary: ActionResult, additional: [ActionResult], final: ActionResult) -> ActionResult`. Ela devolve `primary` com `traversalAfter`/`traversalAfterError` de `final` e `primaryActionError` = o primeiro erro não nulo entre `primary` e `additional` (na ordem).

- [ ] **Step 1: Testes**

```swift
func test_merge_keepsPrimaryError() {
    let r = mergeComposedResults(primary: ActionResult(primaryActionError: "click failed"),
                                 additional: [ActionResult()], final: ActionResult())
    XCTAssertEqual(r.primaryActionError, "click failed")
}
func test_merge_surfacesAdditionalError() {
    let r = mergeComposedResults(primary: ActionResult(),
                                 additional: [ActionResult(), ActionResult(primaryActionError: "type failed")],
                                 final: ActionResult(traversalAfterError: "t"))
    XCTAssertEqual(r.primaryActionError, "type failed")
    XCTAssertEqual(r.traversalAfterError, "t")
}
```

- [ ] **Step 2:** Rodar o `swift test` e ver os testes falharem.
- [ ] **Step 3:** Implementar a função. No laço do modo composto, juntar os resultados num `var additionalResults: [ActionResult]` em vez de `let _ =`, e trocar o bloco "Combine" por `actionResult = mergeComposedResults(...)`.
- [ ] **Step 4:** Separar as duas ideias: antes do `switch params.name`, declarar `var isInputAction = false` e pôr `true` em todo case que hoje faz `hasDiff = true`. O bloco de troca de app passa a usar `if isInputAction` em vez de `if hasDiff`.
- [ ] **Step 5:** Rodar o build, o `swift test` e o `test_mcp.py`.
- [ ] **Step 6:** Commit `fix: surface errors from chained actions and detect app switch in composed mode`.

---

### Task 7: Busca por `element` prefere match exato e visível (achado 6)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`, case `clickTool.name`, modo busca
- Test: `Tests/MCPServerTests/ElementSearchTests.swift`

**Interfaces:**
- Produces: `func rankElementMatches(_ elements: [EnrichedElementData], search: String, role: String?) -> [EnrichedElementData]`. Mantém o filtro atual (texto contém a busca sem diferenciar maiúsculas, tem coordenadas, `w > 0 && h > 0`, prefixo do papel) e ordena de forma estável por: (1) texto igual à busca sem diferenciar maiúsculas, (2) `in_viewport == true`.

- [ ] **Step 1: Testes**

```swift
func test_rank_prefersExactOverSubstring() {
    let els = [el("AXButton", "Autosave"), el("AXButton", "Save")]
    XCTAssertEqual(rankElementMatches(els, search: "save", role: nil).first?.text, "Save")
}
func test_rank_prefersVisible() {
    let els = [el("AXButton", "Save", visible: false), el("AXButton", "Save", visible: true)]
    XCTAssertEqual(rankElementMatches(els, search: "Save", role: nil).first?.in_viewport, true)
}
func test_rank_respectsRoleAndReturnsEmpty() {
    XCTAssertTrue(rankElementMatches([el("AXStaticText", "Save")], search: "Save", role: "AXButton").isEmpty)
}
```

`el` cria um `EnrichedElementData` com x/y/w/h = 10.

- [ ] **Step 2:** Rodar o `swift test` e ver os testes falharem.
- [ ] **Step 3:** Implementar a função e trocar o `.filter { ... }` do handler por `rankElementMatches(enriched.elements, search: elementSearch, role: roleFilter)`. O `guard let match = matches.first` continua igual.
- [ ] **Step 4:** Rodar o build e o `swift test`.
- [ ] **Step 5:** Commit `fix: prefer exact and visible matches in element search`.

---

### Task 8: Fixar a revisão do MacosUseSDK (achado 7)

**Files:**
- Modify: `Package.swift:13`, `Package.resolved`

- [ ] **Step 1:** Trocar `branch: "main"` por `revision: "a2d7866355bca07faf476c5d180c8664b1992f8c"` (a revisão já usada hoje, linha 18 do `Package.resolved`).
- [ ] **Step 2:** Rodar `xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift package resolve` e depois o build. O `Package.resolved` passa a mostrar `"revision"` sem `"branch"`.
- [ ] **Step 3:** Commit `chore: pin MacosUseSDK to a fixed revision`.

---

### Task 9: Remover duplicação (achado 10)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`
- Test: `Tests/MCPServerTests/ArgumentParsingTests.swift`

**Interfaces:**
- Produces:
  - `func hitPoint(from args: [String: Value]?) throws -> CGPoint`: `x`/`y` são obrigatórios; com `width` e `height` devolve o centro.
  - `func activateApp(pid: pid_t) async`: `activate(options: [])` + sleep de 200 ms, só se o app existir.
  - `func optionalPoint(from args: [String: Value]?) -> (x: Int, y: Int)`: para o resumo; usa `(x, y) = (0, 0)` quando falta valor.

- [ ] **Step 1: Testes**

```swift
func test_hitPoint_centersWhenSizeGiven() throws {
    XCTAssertEqual(try hitPoint(from: ["x": 10, "y": 20, "width": 100, "height": 40]), CGPoint(x: 60, y: 40))
}
func test_hitPoint_rawWhenNoSize() throws {
    XCTAssertEqual(try hitPoint(from: ["x": "10", "y": 20.0]), CGPoint(x: 10, y: 20))
}
func test_hitPoint_throwsWithoutY() {
    XCTAssertThrowsError(try hitPoint(from: ["x": 10]))
}
```

- [ ] **Step 2:** Rodar o `swift test` e ver os testes falharem.
- [ ] **Step 3:** Implementar e usar `hitPoint` + `activateApp` em `setValueTool`, `pressAXTool`, `setSelectedTool` e no modo coordenada do `clickTool` (o click só lê `x`/`y` quando não há `element`; mantenha a mensagem de erro atual nesse caso). No `buildCompactSummary`, usar `optionalPoint` nos 6 cases.
- [ ] **Step 4:** Reescrever `getRequiredDouble`/`getRequiredInt` como `guard let v = try getOptionalX(from:key:) else { throw MCPError.invalidParams("Missing required ... '\(key)'") }; return v`.
- [ ] **Step 5:** Rodar o build, o `swift test` e o `test_mcp.py`.
- [ ] **Step 6:** Commit `refactor: share hit point parsing and app activation across tools`.

---

### Task 10: Apagar debug e código morto (achado 11)

**Files:**
- Modify: `Sources/MCPServer/InputGuard.swift`, `Sources/MCPServer/MCPServer.swift`, `.gitignore`
- Delete: `scripts/old_click_test.swift`, `extensions-check.png`

- [ ] **Step 1:** Em `InputGuard.swift`, apagar as 3 escritas `try? ... .write(toFile: "/tmp/macos-use/...")`, o `showOverlay(message:)`, o `isEngaged`, o `onUserCancelled` e a chamada dele, e o `showOverlaySync` (chame `buildAndShowOverlay` direto).
- [ ] **Step 2:** Em `MCPServer.swift`, apagar `serializeToJsonString` e os handlers `ReadResource`, `ListResources` e `ListPrompts` (o servidor só anuncia `tools`).
- [ ] **Step 3:** No `.gitignore`, apagar o bloco de Next.js/Vercel/env/SEO (de `node_modules/` para baixo, mantendo `node_modules/`, porque o `package.json` existe) e adicionar `.worktree/`, se o setup ainda não tiver adicionado.
- [ ] **Step 4: Verificar:** `grep -rn "tmp/macos-use\|serializeToJsonString\|onUserCancelled\|ReadResource" Sources` não retorna nada. Rodar o build, o `swift test` e o `test_mcp.py` (o `initialize` ainda responde).
- [ ] **Step 5:** Commit `chore: remove debug marker files and dead code`.

---

### Task 11: Auto-scroll sem varrer a árvore a cada passo (achado 13)

**Files:**
- Modify: `Sources/MCPServer/MCPServer.swift`, `scrollIntoViewIfNeeded`, CASE 1

- [ ] **Step 1:** Em cada passo, antes do `findElementByText`, checar o elemento já encontrado: se `targetElement` tem frame com centro dentro de `windowBounds.insetBy(dx: 0, dy: 15)`, retornar esse centro. Só chamar `findElementByText` (a varredura completa) quando `step % 5 == 0`, porque o elemento pode ter sido recriado pelo app. Apagar o bloco "Debug: check where the target element currently is", que já lê o mesmo frame.
- [ ] **Step 2:** Rodar o build.
- [ ] **Step 3: Verificação manual** com o `test_mcp.py`: clicar num item fora da tela numa lista longa (barra lateral do Mail ou do Finder). O log mostra `found ... after N steps` e o clique acerta o item.
- [ ] **Step 4:** Commit `perf: check cached element frame before full tree search while scrolling`.

---

## Fim

- [ ] Rodar o build, o `swift test` (todos passam) e o `python3 scripts/test_mcp.py`.
- [ ] Pedir ao usuário para reconectar o MCP (`/mcp`) e testar uma chamada real.
- [ ] Usar superpowers:finishing-a-development-branch.
