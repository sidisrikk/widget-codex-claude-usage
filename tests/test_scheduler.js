// Execute the production QML JavaScript, with only Qt objects and time mocked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const qml = fs.readFileSync('contents/ui/UsageController.qml', 'utf8');
const mainQml = fs.readFileSync('contents/ui/main.qml', 'utf8');
const fullQml = fs.readFileSync('contents/ui/CodexSection.qml', 'utf8');
const claudeQml = fs.readFileSync('contents/ui/ClaudeSection.qml', 'utf8');
const headerQml = fs.readFileSync('contents/ui/SectionHeader.qml', 'utf8');
const compactQml = fs.readFileSync('contents/ui/CompactRepresentation.qml', 'utf8');

function block(start, source = qml) {
    const open = source.indexOf('{', start);
    let depth = 1, quote = '', comment = '';
    for (let i = open + 1; i < source.length; i++) {
        const ch = source[i], next = source[i + 1];
        if (comment) {
            if (comment === 'line' && ch === '\n') comment = '';
            else if (comment === 'block' && ch === '*' && next === '/') { comment = ''; i++; }
        } else if (quote) {
            if (ch === '\\') i++;
            else if (ch === quote) quote = '';
        } else if (ch === '"' || ch === "'") quote = ch;
        else if (ch === '/' && next === '/') { comment = 'line'; i++; }
        else if (ch === '/' && next === '*') { comment = 'block'; i++; }
        else if (ch === '{') depth++;
        else if (ch === '}' && --depth === 0) return source.slice(open + 1, i);
    }
    throw Error('Unclosed production block');
}

function harness(provider = 'codex') {
    let now = 1000000;
    const launches = [], disconnects = [];
    const timer = { running: false, interval: 0, starts: 0,
        stop() { this.running = false; },
        restart() { this.running = true; this.starts++; } };
    const root = {};
    const header = { controller: root };
    function MockDate(...args) { return args.length ? new Date(...args) : new Date(now); }
    MockDate.now = () => now;
    const context = vm.createContext({ controller: root, codex: root, claude: root, header, pollTimer: timer, Date: MockDate,
        Qt: { resolvedUrl: url => 'file:///mock%20dir/' + url.split('/').pop(), formatDateTime: date => `saved@${date.getTime() / 1000}` },
        Plasmoid: { configuration: { showPercentageLeft: true }, setAction() {} },
        i18n: (text, ...args) => args.reduce((result, value, index) => result.replace(`%${index + 1}`, value), text),
        console: { warn() {} },
        executableSource: { connectSource: s => launches.push(s) },
        disconnectSource: s => disconnects.push(s) });
    for (const match of qml.matchAll(/^\s*(readonly )?property \w+ (\w+): (.+)$/gm)) {
        if (match[1]) Object.defineProperty(root, match[2], {
            get: () => vm.runInContext(`(function() { with (controller) { return (${match[3]}); } })()`, context) });
        else root[match[2]] = vm.runInContext(match[3], context);
    }
    for (const match of qml.matchAll(/function (\w+)\(([^)]*)\)\s*\{/g)) {
        const fn = vm.runInContext(`(function(${match[2]}) {${block(match.index)}})`, context);
        root[match[1]] = context[match[1]] = fn;
    }
    root.provider = provider;
    const completion = vm.runInContext(`(function(sourceName, data) {${block(qml.indexOf('onNewData:'))}})`, context);
    const pollStart = qml.indexOf('id: pollTimer');
    const poll = vm.runInContext(`(function() {${block(qml.indexOf('onTriggered:', pollStart))}})`, context);
    const startup = vm.runInContext(`(function() {${block(qml.indexOf('Component.onCompleted:'))}})`, context);
    const clockStart = qml.indexOf('interval: 1000', pollStart);
    const clockExpression = qml.slice(clockStart).match(/onTriggered: (.+)/)[1];
    const clock = () => vm.runInContext(clockExpression, context);
    return { root, context, timer, launches, disconnects, poll, startup, clock,
        advance(ms) { now += ms; }, now: () => now,
        deliver(data, source = root.activeUsageSource, exitCode = 0) {
            completion(source, { stdout: typeof data === 'string' ? data : JSON.stringify(data), 'exit code': exitCode });
        } };
}

function evaluateBinding(source, expression, h) {
    return vm.runInContext(`(function() { return (${expression}); })()`, h.context);
}

function failure(extra = {}) {
    return { status: 'offline', retryable: true, retry_after_seconds: null,
        has_data: false, cached: false, attempted_at: 123, updated_at: null,
        updated_formatted: null, error_message: 'Unavailable', ...extra };
}
function snapshot(extra = {}) {
    return { ...failure(), status: 'ok', retryable: false, has_data: true,
        plan: 'Pro', used_percent: 72, left_percent: 28, cycle_elapsed_percent: 42.5,
        cycle_elapsed_days: 3, cycle_remaining_days: 4, reset_in: '4d', reset_formatted: 'Friday',
        resets: [{ id: 'weekly', label: 'Weekly', kind: 'weekly', countdown: '4d',
            date: 'Friday', detail: '28%', is_urgent: false, remaining_seconds: 345600 }],
        allowed: false, limit_reached: true, updated_at: 111, updated_formatted: '12:34:56', ...extra };
}

const tests = [];
function test(name, fn) { tests.push([name, fn]); }
test('completion-based 15/30/60/120/300/600/600; busy and success reset', () => {
    const h = harness(); h.startup();
    assert.equal(h.launches.length, 1); assert.equal(h.timer.running, false);
    for (const seconds of [15, 30, 60, 120, 300, 600, 600]) {
        assert.equal(h.root.refreshUsage(), false);
        h.advance(4500); // Fetch duration must not consume any of the wait.
        h.deliver(failure());
        assert.equal(h.root.nextRefreshAt, h.now() + seconds * 1000);
        assert.equal(h.timer.interval, seconds * 1000);
        assert.equal(h.root.isRetryWaiting, true); assert.equal(h.root.isRefreshing, false);
        h.advance(seconds * 1000 - 1); h.poll(); assert.equal(h.root.isRefreshing, false);
        h.advance(1); h.poll(); assert.equal(h.root.isRefreshing, true);
    }
    h.deliver(snapshot()); assert.equal(h.root.retryCount, 0);
    assert.equal(h.timer.interval, 600000); assert.equal(h.root.isRetryWaiting, false);
    h.root.refreshUsage(); h.deliver(failure()); assert.equal(h.timer.interval, 15000);
});
test('permanent, malformed and unexpected responses use normal waits without resetting backoff', () => {
    const h = harness(); h.root.refreshInterval = 90;
    h.root.refreshUsage(); h.deliver(failure());
    const invalid = ['{', '', 'null', '{}', '[]', snapshot({ status: 'surprise' }),
        snapshot({ left_percent: '28' }), snapshot({ resets: [null] }),
        snapshot({ updated_at: null }), failure({ retry_after_seconds: -1 }),
        failure({ retryable: 'true' }), failure({ status: 'no_auth' }),
        failure({ status: 'error', retryable: false })];
    for (const data of invalid) {
        h.root.refreshUsage(); h.deliver(data);
        assert.equal(h.timer.interval, 90000); assert.equal(h.root.retryCount, 1);
        assert.equal(h.root.isRetryWaiting, false);
    }
    h.root.refreshUsage(); h.deliver(failure()); assert.equal(h.timer.interval, 30000);
});
test('429 later-of backoff/cooldown, manual guard, reactive countdown and long timer chunks', () => {
    const h = harness(); h.root.refreshUsage();
    h.deliver(failure({ status: 'error', retry_after_seconds: 2 }));
    assert.equal(h.timer.interval, 15000); assert.equal(h.root.refreshUsage(), false);
    h.advance(2000); h.clock(); assert.equal(h.root.serverCooldownSeconds, 0);
    assert.equal(h.root.nextRefreshSeconds, 13);
    assert.equal(h.root.refreshUsage(), true); assert.equal(h.root.refreshUsage(), false);
    h.deliver(failure({ status: 'error', retry_after_seconds: 1800 }));
    assert.equal(h.timer.interval, 1800000); assert.equal(h.root.refreshUsage(), false);
    h.advance(1800000); h.poll(); assert.equal(h.root.isRefreshing, true);
    const longSeconds = 5000000;
    h.deliver(failure({ status: 'error', retry_after_seconds: longSeconds }));
    const deadline = h.root.nextRefreshAt;
    assert.equal(deadline, h.now() + longSeconds * 1000);
    assert.equal(h.timer.interval, 2147483647);
    while (h.now() < deadline) {
        h.advance(h.timer.interval); h.poll();
        assert.equal(h.root.nextRefreshAt, h.now() < deadline ? deadline : 0);
    }
    assert.equal(h.root.isRefreshing, true);
});
test('unconditional disconnect, duplicate completions and launchCodex isolation', () => {
    const h = harness(); h.startup(); const source = h.root.activeUsageSource;
    h.root.launchCodex(); const codex = h.launches[1];
    h.deliver(snapshot(), codex); assert.equal(h.root.isRefreshing, true);
    assert.equal(h.timer.starts, 0); assert.equal(h.root.hasData, false);
    h.deliver(failure(), source); const deadline = h.root.nextRefreshAt;
    h.deliver(snapshot(), source); h.deliver('', codex);
    assert.equal(h.root.nextRefreshAt, deadline); assert.equal(h.root.retryCount, 1);
    assert.equal(h.timer.starts, 1); assert.equal(h.disconnects.length, 4);
    assert.equal(h.root.hasData, false);
});

test('executable paths are shell-quoted including apostrophes', () => {
    const h = harness(); h.startup();
    assert.equal(h.launches[0], "python3 '/mock dir/fetch_usage.py'");
    assert.equal(h.root.shellQuote("/tmp/Codex user's/fetch usage.py"),
        "'/tmp/Codex user'\\''s/fetch usage.py'");
});
test('all authentication and sign-in states are red', () => {
    const h = harness();
    const start = qml.indexOf('function getStatusColor');
    const getStatusColor = vm.runInContext(
        `(function() { with (controller) {${block(start)}} })`, h.context);
    h.root.leftPercent = 75; h.root.limitReached = false;
    for (const status of ['auth_error', 'auth_expired', 'no_auth', 'no_token']) {
        h.root.status = status;
        assert.equal(getStatusColor(), '#e74c3c', status);
    }
});
test('full cache hydration on startup, no-data and invalid-snapshot memory preservation', () => {
    const h = harness(); h.startup();
    const cached = snapshot({ status: 'offline', retryable: true, cached: true });
    h.deliver(cached);
    const mapping = { plan: 'plan', usedPercent: 'used_percent', leftPercent: 'left_percent',
        cycleElapsedPercent: 'cycle_elapsed_percent', cycleElapsedDays: 'cycle_elapsed_days',
        cycleRemainingDays: 'cycle_remaining_days', resetIn: 'reset_in', resetFormatted: 'reset_formatted',
        resetsList: 'resets', allowed: 'allowed', limitReached: 'limit_reached',
        lastSuccessfulAt: 'updated_at', lastUpdated: 'updated_formatted' };
    const check = () => {
        assert.equal(h.root.hasData, true);
        for (const [key, field] of Object.entries(mapping)) {
            assert.equal(JSON.stringify(h.root[key]), JSON.stringify(cached[field]), key);
        }
    };
    check(); assert.equal(h.root.cached, true); assert.equal(h.root.attemptedAt, 123);
    h.root.refreshUsage(); h.deliver(failure()); check();
    h.root.refreshUsage(); h.deliver(snapshot({ resets: [{}], plan: 'bad' })); check();
    assert.equal(h.root.status, 'error'); assert.equal(h.timer.interval, 600000);
});

test('nonzero process exit is a permanent error even with valid stdout', () => {
    const h = harness(); h.startup(); h.deliver(snapshot());
    h.root.refreshUsage(); h.deliver(failure());
    h.root.refreshUsage(); h.deliver(snapshot({ left_percent: 99 }), h.root.activeUsageSource, 1);
    assert.equal(h.root.leftPercent, 28);
    assert.equal(h.root.status, 'error');
    assert.equal(h.root.errorMessage, 'Usage fetch failed');
    assert.equal(h.root.retryCount, 1);
    assert.equal(h.timer.interval, 600000);
});

test('older disk cache cannot replace memory; newer cache and backwards-clock success can', () => {
    const h = harness(); h.startup();
    const current = snapshot({ updated_at: 200, left_percent: 80, plan: 'new' });
    h.deliver(current);
    const older = snapshot({ status: 'offline', retryable: true, cached: true,
        updated_at: 100, left_percent: 28, plan: 'old', attempted_at: 300 });
    h.root.refreshUsage(); h.deliver(older);
    assert.equal(h.root.leftPercent, 80); assert.equal(h.root.plan, 'new');
    assert.equal(h.root.lastSuccessfulAt, 200);
    assert.equal(h.root.status, 'offline'); assert.equal(h.root.attemptedAt, 300);
    assert.equal(h.root.retryable, true); assert.equal(h.timer.interval, 15000);
    assert.match(h.root.noticeText, /saved@200/);
    h.root.refreshUsage(); h.deliver({ ...older, updated_at: 200, left_percent: 70 });
    assert.equal(h.root.leftPercent, 80); // An older disk snapshot can share the success's second.
    h.root.refreshUsage(); h.deliver({ ...older, updated_at: 250, left_percent: 60 });
    assert.equal(h.root.leftPercent, 60); assert.equal(h.root.lastSuccessfulAt, 250);
    h.root.refreshUsage(); h.deliver(snapshot({ updated_at: 50, left_percent: 90 }));
    assert.equal(h.root.leftPercent, 90); assert.equal(h.root.lastSuccessfulAt, 50);
    assert.equal(h.root.retryCount, 0); assert.equal(h.timer.interval, 600000);
});

test('legacy and invalid cache cannot poison production network recovery', () => {
    const payloads = JSON.parse(execFileSync('python3', ['-c', `
import contextlib, importlib.util, io, json
from unittest.mock import mock_open, patch
spec = importlib.util.spec_from_file_location('backend', 'contents/scripts/fetch_usage.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
results = []
for invalid in (False, True):
    cached = backend.build_snapshot({'rate_limit': {'primary_window': {'used_percent': 25}}}, [])
    cached['updated_at'] = 100
    cached['resets'].append({'id': None, 'label': 'Credit', 'kind': 'credit',
                            'countdown': 'Available', 'date': '--', 'detail': 'Credit token',
                            'is_urgent': False, 'remaining_seconds': float('inf')})
    if invalid:
        cached['plan'] = None
    out = io.StringIO()
    with patch.object(backend.os.path, 'exists', return_value=True), \\
         patch('builtins.open', mock_open(read_data=json.dumps(cached))), \\
         patch.object(backend, 'fetch_result', side_effect=TimeoutError()), contextlib.redirect_stdout(out):
        backend.fetch()
    results.append(json.loads(out.getvalue()))
print(json.dumps(results, allow_nan=False))
`], { encoding: 'utf8' }));
    for (const [index, payload] of payloads.entries()) {
        const h = harness(); h.startup(); h.deliver(payload);
        assert.equal(h.root.status, 'offline');
        assert.equal(h.root.hasData, index === 0);
        assert.equal(h.timer.interval, 15000);
        const memory = harness(); memory.startup();
        memory.deliver(snapshot({ updated_at: 200, left_percent: 80 }));
        memory.root.refreshUsage(); memory.deliver(payload);
        assert.equal(memory.root.leftPercent, 80);
        assert.equal(memory.root.lastSuccessfulAt, 200);
        assert.equal(memory.timer.interval, 15000);
    }
});

test('synthetic backend fetch JSON with malformed optional credits passes production validation', () => {
    // All filesystem, credentials, TLS and HTTP dependencies are mocked in-process.
    const payloads = JSON.parse(execFileSync('python3', ['-c', `
import contextlib, importlib.util, io, json
from unittest.mock import Mock, mock_open, patch
spec = importlib.util.spec_from_file_location('backend', 'contents/scripts/fetch_usage.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
results = []
for summary in (None, [], 'bad', {'available_count': None}, {'available_count': '2'},
                {'available_count': 2.5}, {'available_count': True}, {'available_count': -1}):
    for credits in ([], [None], None, [{'id': value, 'expires_at': {'bad': 'date'}}
                                     for value in (None, 42, True, [], {}, 'valid')]):
        usage = {'plan_type': 'Plus', 'rate_limit': {'primary_window': {'used_percent': 25}},
                 'rate_limit_reset_credits': summary}
        out = io.StringIO()
        with patch.object(backend, 'load_cache', return_value=None), \\
             patch.object(backend.os.path, 'exists', return_value=True), \\
             patch('builtins.open', mock_open(read_data='{"tokens":{"access_token":"synthetic"}}')), \\
             patch.object(backend.ssl, 'create_default_context', return_value=Mock()), \\
             patch.object(backend, 'request_json', side_effect=[usage, {'credits': credits}]), \\
             patch.object(backend, 'save_cache'), contextlib.redirect_stdout(out):
            backend.fetch()
        results.append(json.loads(out.getvalue()))
print(json.dumps(results, allow_nan=False))
`], { encoding: 'utf8' }));
    assert.equal(payloads.length, 32);
    for (const payload of payloads) {
        const h = harness(); h.startup();
        assert.equal(payload.status, 'ok');
        assert.equal(h.root.validSnapshot(payload), true);
        h.deliver(payload);
        assert.equal(h.root.status, 'ok'); assert.equal(h.root.hasData, true);
        assert.equal(h.root.leftPercent, 75);
    }
    const h = harness();
    assert.equal(h.root.validSnapshot(snapshot({ resets: [{ ...snapshot().resets[0], id: null }] })), false);
});

test('stale and unavailable notices, cooldown button, compact quota guards, and recovery', () => {
    const h = harness(); h.startup(); h.deliver(snapshot());
    h.root.refreshUsage(); h.deliver(failure({ status: 'error', retry_after_seconds: 30 }));
    assert.match(h.root.noticeText, /Showing saved quota from saved@111/);
    assert.match(h.root.noticeText, /Retry in 30 seconds/);
    const enabled = headerQml.match(/enabled: (.+)/)[1];
    assert.equal(evaluateBinding(fullQml, enabled, h), false);
    h.advance(10000); h.clock();
    assert.match(h.root.noticeText, /Retry in 20 seconds/);
    assert.match(h.root.noticeText, /Server cooldown: refresh available in 20 seconds/);

    const noData = harness(); noData.startup(); noData.deliver(failure());
    assert.match(noData.root.noticeText, /Quota unavailable/);
    assert.match(noData.root.noticeText, /Retry in 15 seconds/);
    assert.equal(noData.root.leftPercent, 100); // Stored default is never presented as a quota.
    const displayExpression = compactQml.match(/function displayPercent\(usage\) \{\s*return (.+);/)[1]
        .replace(/usage\./g, 'controller.');
    assert.equal(evaluateBinding(compactQml, displayExpression, noData), 0);
    assert.equal(evaluateBinding(compactQml, displayExpression, h), 28);
    for (const [name, liveValue] of [['quotaValue', '28% left'], ['timeValue', '4d left']]) {
        const expression = fullQml.match(new RegExp(`objectName: "${name}"\\s+text: (.+)`))[1];
        assert.equal(evaluateBinding(fullQml, expression, noData), '—');
        assert.equal(evaluateBinding(fullQml, expression, h), liveValue);
    }
    for (const [name, liveWidth] of [['quotaFill', 28], ['timeFill', 57.5]]) {
        const expression = fullQml.match(new RegExp(`objectName: "${name}"[\\s\\S]*?width: (.+)`))[1];
        const timeExpression = fullQml.match(/readonly property real timeRemainingPercent: (.+)/)[1];
        for (const [state, expected] of [[noData, 0], [h, liveWidth]]) {
            state.context.parent = { height: 8, width: 100,
                timeRemainingPercent: evaluateBinding(fullQml, timeExpression, state) };
            assert.ok(Math.abs(evaluateBinding(fullQml, expression, state) - expected) < 1e-9);
        }
    }
    noData.root.isRefreshing = true;
    assert.match(noData.root.noticeText, /Quota unavailable/);
    assert.match(noData.root.noticeText, /Refreshing…/);

    h.advance(20000); h.clock();
    h.root.refreshUsage();
    assert.match(h.root.noticeText, /Showing saved quota from saved@111/);
    assert.match(h.root.noticeText, /Refreshing…/);
    assert.doesNotMatch(h.root.noticeText, /Retry in/);
    h.deliver(snapshot());
    assert.doesNotMatch(h.root.noticeText, /saved@|Retry in|Server cooldown/);
    assert.equal(evaluateBinding(fullQml, enabled, h), true);
});

test('null reset remaining_seconds is unknown, not expired', () => {
    const tooltipBlock = fullQml.slice(fullQml.indexOf('text: {', fullQml.indexOf('PlasmaComponents.ToolTip')));
    const expression = tooltipBlock.match(/var isExp = (.*);/)[1];
    const context = vm.createContext({ modelData: { countdown: 'Unknown', remaining_seconds: null } });
    assert.equal(vm.runInContext(expression, context), false);
});

function claudeWindow(extra = {}) {
    return { id: 'weekly', label: 'Weekly', used_percent: 18, left_percent: 82, window_seconds: 604800,
        reset_in: '4d 6h 10m', reset_formatted: 'Fri, 30 Oct 20:00', remaining_seconds: 367800,
        time_left_percent: 60.8, time_left_text: '4.3d left', limit_reached: false, ...extra };
}
function claudeSnapshot(extra = {}) {
    return { ...failure(), status: 'ok', retryable: false, has_data: true, plan: 'Pro',
        used_percent: 64, left_percent: 36, limit_reached: false,
        windows: [claudeWindow({ id: 'session', label: 'Session (5h)', used_percent: 64, left_percent: 36,
            window_seconds: 18000, reset_in: '3h 12m', reset_formatted: 'Wed, 28 Oct 23:40',
            remaining_seconds: 11520, time_left_percent: 64, time_left_text: '3.2h left' }), claudeWindow()],
        updated_at: 111, updated_formatted: '12:34:56', ...extra };
}
function claudeHarness() {
    const h = harness('claude'); h.root.displayName = 'Claude'; h.root.scriptName = 'fetch_claude_usage.py';
    return h;
}

test('Claude snapshots validate per provider and hydrate only windows', () => {
    const h = claudeHarness(); h.startup();
    h.deliver(claudeSnapshot());
    assert.equal(h.root.status, 'ok'); assert.equal(h.root.hasData, true);
    assert.equal(h.root.leftPercent, 36); assert.equal(h.root.plan, 'Pro');
    assert.equal(JSON.stringify(h.root.windowsList), JSON.stringify(claudeSnapshot().windows));
    assert.equal(JSON.stringify(h.root.resetsList), '[]');
    assert.equal(h.timer.interval, 600000);
    const invalid = [snapshot(), claudeSnapshot({ windows: [] }), claudeSnapshot({ windows: [null] }),
        claudeSnapshot({ windows: [claudeWindow({ time_left_percent: '1' })] }),
        claudeSnapshot({ windows: [claudeWindow({ remaining_seconds: undefined })] }),
        claudeSnapshot({ windows: [claudeWindow({ limit_reached: 'no' })] }),
        claudeSnapshot({ windows: [claudeWindow({ reset_in: null })] }),
        claudeSnapshot({ left_percent: Infinity }), claudeSnapshot({ plan: 7 })];
    for (const data of invalid) {
        const fresh = claudeHarness(); fresh.startup(); fresh.deliver(data);
        assert.equal(fresh.root.status, 'error'); assert.equal(fresh.root.hasData, false);
        h.root.refreshUsage(); h.deliver(data);
        assert.equal(h.root.leftPercent, 36); assert.equal(h.root.windowsList.length, 2);
    }
    const codex = harness(); codex.startup(); codex.deliver(claudeSnapshot());
    assert.equal(codex.root.status, 'error'); assert.equal(codex.root.hasData, false);
    const unknown = claudeHarness(); unknown.startup();
    unknown.deliver(claudeSnapshot({ windows: [claudeWindow({ remaining_seconds: null })] }));
    assert.equal(unknown.root.status, 'ok');
});

test('Claude pairs gate placeholders, reset labels and per-window colors', () => {
    const noData = claudeHarness(); noData.startup(); noData.deliver(failure({ status: 'auth_expired', retryable: false }));
    const live = claudeHarness(); live.startup(); live.deliver(claudeSnapshot());
    const modelExpression = claudeQml.match(/model: (claudeSection\.claude\.hasData .+)/)[1];
    const quotaExpression = claudeQml.match(/objectName: "claudeQuotaValue"\s+text: (.+)/)[1];
    const timeExpression = claudeQml.match(/objectName: "claudeTimeValue"\s+text: (.+)/)[1];
    const resetExpression = claudeQml.match(/objectName: "claudeResetIn"\s+text: ([\s\S]+?)\n\s+font/)[1];
    const placeholders = [{ id: 'session', label: 'Session (5h)' }, { id: 'weekly', label: 'Weekly' }];
    for (const h of [noData, live]) {
        h.context.claudeSection = { claude: h.root, placeholderWindows: placeholders };
        h.context.pair = { live: h.root.hasData };
    }
    const models = evaluateBinding(claudeQml, modelExpression, noData);
    assert.equal(models, placeholders);
    assert.equal(noData.root.needsSignIn, true);
    assert.equal(noData.root.statusSummary, 'Sign-in required');
    for (const modelData of models) {
        noData.context.modelData = modelData;
        for (const expression of [quotaExpression, timeExpression, resetExpression]) {
            assert.equal(evaluateBinding(claudeQml, expression, noData), '—');
        }
    }
    const expected = [['36% left', '3.2h left', 'resets 3h 12m'], ['82% left', '4.3d left', 'resets 4d 6h 10m']];
    evaluateBinding(claudeQml, modelExpression, live).forEach((modelData, index) => {
        live.context.modelData = modelData;
        assert.deepEqual([quotaExpression, timeExpression, resetExpression]
            .map(expression => evaluateBinding(claudeQml, expression, live)), expected[index]);
    });
    live.context.modelData = claudeWindow({ reset_formatted: '--', reset_in: 'Not started' });
    assert.equal(evaluateBinding(claudeQml, resetExpression, live), 'Not started');
    assert.equal(live.root.colorFor(82, false), '#2ecc71');
    assert.equal(live.root.colorFor(36, false), '#f39c12');
    assert.equal(live.root.colorFor(20, false), '#e74c3c');
    assert.equal(live.root.colorFor(90, true), '#e74c3c');
    live.root.refreshUsage(); live.deliver({ ...claudeSnapshot(), status: 'offline', retryable: true, cached: true });
    assert.equal(live.root.colorFor(90, false), '#f39c12');
    assert.equal(noData.root.colorFor(90, false), '#e74c3c');
});

test('main refresh action and tooltip keep providers independent', () => {
    const codex = harness(); codex.startup(); codex.deliver(snapshot());
    codex.root.refreshUsage(); codex.deliver(failure({ status: 'error', retry_after_seconds: 120 }));
    const claude = claudeHarness(); claude.startup(); claude.deliver(claudeSnapshot());
    const main = vm.createContext({ codexUsage: codex.root, claudeUsage: claude.root,
        i18n: (text, ...args) => args.reduce((result, value, index) => result.replace(`%${index + 1}`, value), text) });
    const refreshAll = vm.runInContext(`(function() {${block(mainQml.indexOf('function action_refresh'), mainQml)}})`, main);
    const toolTip = vm.runInContext(`(function(usage) {${block(mainQml.indexOf('function providerToolTip'), mainQml)}})`, main);
    const enabled = headerQml.match(/enabled: (.+)/)[1];
    codex.context.header = { controller: codex.root }; claude.context.header = { controller: claude.root };
    assert.equal(evaluateBinding(headerQml, enabled, codex), false);
    assert.equal(evaluateBinding(headerQml, enabled, claude), true);
    refreshAll();
    assert.equal(codex.launches.length, 2); assert.equal(codex.root.isRefreshing, false);
    assert.equal(claude.launches.length, 2); assert.equal(claude.root.isRefreshing, true);
    assert.match(claude.launches[1], /fetch_claude_usage\.py/);
    assert.equal(evaluateBinding(headerQml, enabled, claude), false);
    claude.deliver(claudeSnapshot({ updated_at: 222 }));
    assert.match(toolTip(claude.root), /^Claude: 36% left\nSession \(5h\): 36% left · resets 3h 12m\nWeekly: 82% left/);
    assert.match(toolTip(codex.root), /^Codex: Showing saved quota/);
    assert.equal(codex.root.serverCooldownSeconds, 120); assert.equal(claude.root.serverCooldownSeconds, 0);
});

test('synthetic Claude backend JSON passes production validation', () => {
    // Credentials, cache, TLS and HTTP are mocked in-process; the token is synthetic.
    const payloads = JSON.parse(execFileSync('python3', ['-c', `
import contextlib, importlib.util, io, json, time
from unittest.mock import Mock, mock_open, patch
spec = importlib.util.spec_from_file_location('claude', 'contents/scripts/fetch_claude_usage.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
future = int((time.time() + 3600) * 1000)
usage = {'five_hour': {'utilization': 64.0, 'resets_at': '2099-01-01T00:00:00+00:00'},
         'seven_day': {'utilization': 18.5, 'resets_at': None, 'locked_reason': None},
         'seven_day_sonnet': {'utilization': 100, 'resets_at': '2000-01-01T00:00:00Z'},
         'seven_day_opus': None, 'extra_usage': {'utilization': None}, 'limits': []}
results = []
for expires in (future, 0, None):
    creds = {'claudeAiOauth': {'accessToken': 'synthetic', 'expiresAt': expires, 'subscriptionType': 'max'}}
    out = io.StringIO()
    with patch.object(backend, 'load_cache', return_value=None), \\
         patch.object(backend.os.path, 'exists', return_value=True), \\
         patch('builtins.open', mock_open(read_data=json.dumps(creds))), \\
         patch.object(backend.ssl, 'create_default_context', return_value=Mock()), \\
         patch.object(backend, 'request_json', return_value=usage), \\
         patch.object(backend, 'save_cache'), contextlib.redirect_stdout(out):
        backend.fetch()
    results.append(json.loads(out.getvalue()))
print(json.dumps(results, allow_nan=False))
`], { encoding: 'utf8' }));
    assert.deepEqual(payloads.map(payload => payload.status), ['ok', 'auth_expired', 'ok']);
    for (const payload of payloads) {
        const h = claudeHarness(); h.startup(); h.deliver(payload);
        assert.equal(h.root.status, payload.status);
        assert.equal(h.root.hasData, payload.status === 'ok');
        if (payload.status !== 'ok') continue;
        assert.equal(h.root.validSnapshot(payload), true);
        assert.equal(h.root.plan, 'Max'); assert.equal(h.root.leftPercent, 0);
        assert.equal(h.root.limitReached, true);
        assert.equal(h.root.windowsList.map(window => window.id).join(), 'session,weekly,weekly_sonnet');
    }
});

for (const [name, fn] of tests) { fn(); console.log(`PASS ${name}`); }
console.log(`${tests.length} focused scheduler tests passed (production functions/handlers).`);
