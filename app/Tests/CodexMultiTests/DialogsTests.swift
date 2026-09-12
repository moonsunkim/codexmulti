import Foundation
import XCTest
@testable import CodexMulti




final class DialogsTests: XCTestCase {



    private func exported(_ name: String) throws -> Projection {
        try decode("viewstate-\(name).json")
    }

    private func decode(_ file: String) throws -> Projection {
        try JSONDecoder().decode(Projection.self, from: Data(contentsOf: Fixtures.bridgeDirectory.appending(path: file)))
    }



    private static let states: [(fixture: String, target: DialogTarget)] = [
        ("failover-switch-open", .failoverSwitch),
        ("clear-cooldown-open", .clearCooldown),
        ("rename-open", .rename),
        ("remove-plain-open", .remove(.plain)),
        ("remove-mapped-open", .remove(.mapped)),
        ("remove-mapped-pause-requested", .remove(.mappedPaused)),
        ("remove-mapped-can-finish", .remove(.mappedPaused)),
        ("reset-review", .reset(.review)),
        ("reset-armed", .reset(.armed)),
        ("reset-dispatched-pending", .reset(.dispatched)),
        ("reset-dispatched-settled-cleared", .reset(.dispatched)),
        ("reset-dispatched-settled-unsent", .reset(.dispatched)),
        ("reset-settled-clear-failed", .reset(.dispatched)),
        ("reset-blocked-no-credit", .reset(.blocked)),
        ("reset-blocked-pending", .reset(.blockedRetry)),
    ]

    private func shell(_ state: (fixture: String, target: DialogTarget)) throws -> ShellState {
        try exported(state.fixture).shell
    }




    func testPresentedFollowsTheShellOpenFlags() throws {
        XCTAssertNil(DialogModel.presented(try decode("viewstate-empty-attached.json").shell))
        for name in ["add-account-empty", "add-account-valid", "add-account-in-flight"] {
            XCTAssertEqual(DialogModel.presented(try exported(name).shell), .addAccount, name)
        }
        for state in Self.states {
            XCTAssertEqual(DialogModel.presented(try shell(state)), state.target.kind, state.fixture)
        }
    }



    func testAddAccountSheetUsesEveryProjectedStringAndEnablement() throws {
        let empty = try exported("add-account-empty").shell
        let valid = try exported("add-account-valid").shell
        let busy = try exported("add-account-in-flight").shell

        XCTAssertEqual(empty.add_account.title, "Add Codex account")
        XCTAssertEqual(empty.add_account.explanation_text,
                       "Name this account before opening the browser to sign in.")
        XCTAssertEqual(empty.add_account.confirm_label, "Sign in…")
        XCTAssertEqual(empty.add_account.cancel_label, "Cancel")
        XCTAssertEqual(busy.add_account.progress_text, "Add account in progress · Codex")

        let emptySpec = DialogModel.spec(.addAccount, shell: empty, addAccountDraft: "Owner Work")
        XCTAssertFalse(emptySpec.button(.confirm)?.enabled ?? true,
                       "the button follows the core projection, not a shell validity guess")
        XCTAssertEqual(emptySpec.button(.cancel)?.label, empty.add_account.cancel_label)
        XCTAssertEqual(emptySpec.button(.confirm)?.label, empty.add_account.confirm_label)

        let validSpec = DialogModel.spec(.addAccount, shell: valid,
                                         addAccountDraft: "  Owner Work\n")
        XCTAssertTrue(validSpec.button(.confirm)?.enabled ?? false)
        XCTAssertEqual(validSpec.button(.confirm)?.intent,
                       .commit_add_account(label: "Owner Work"))

        let busySpec = DialogModel.spec(.addAccount, shell: busy,
                                        addAccountDraft: busy.add_account.initial_label)
        XCTAssertEqual(busySpec.buttons.map(\.enabled), [false, false])
        XCTAssertFalse(busySpec.isEnabled(.field))
        XCTAssertEqual(DialogModel.FocusModel(busySpec).cycle, [])
    }

    func testAddAccountReturnCommitsTrimmedDraftAndEscapeCancels() throws {
        let shell = try exported("add-account-empty").shell
        let spec = DialogModel.spec(.addAccount, shell: shell, addAccountDraft: "Owner Work")
        let focus = DialogModel.FocusModel(spec)

        XCTAssertEqual(focus.focused, .field)
        XCTAssertEqual(focus.returnKey(addAccountDraft: "  Owner Work\n"),
                       .commit_add_account(label: "Owner Work"))
        XCTAssertNil(focus.returnKey(addAccountDraft: " \t\n "))
        XCTAssertEqual(focus.escape(), .cancel_add_account)
        XCTAssertEqual(DialogModel.addAccountCommitIntent(shell.add_account,
                                                          draft: "  Owner Work  "),
                       .commit_add_account(label: "Owner Work"))
    }

    func testAddAccountSheetSourceRendersProjectionVerbatim() throws {
        let root = Fixtures.bridgeDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Sources/CodexMulti/Dialogs/Sheets.swift"),
                                encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "struct AddAccountSheet: View"))
        let end = try XCTUnwrap(source.range(of: "struct FailoverSwitchSheet: View"))
        let add = source[start.lowerBound..<end.lowerBound]

        for projected in ["flow.title", "flow.explanation_text",
                          "flow.progress_text", "flow.error_text"] {
            XCTAssertTrue(add.contains(projected), "missing projected string: \(projected)")
        }
        XCTAssertTrue(add.contains(".disabled(flow.in_flight)"))
        XCTAssertTrue(add.contains("DialogModel.addAccountCommitIntent(flow, draft: draft)"))

        let model = try String(contentsOf: root.appending(path: "Sources/CodexMulti/Dialogs/DialogModel.swift"),
                               encoding: .utf8)
        XCTAssertTrue(model.contains("Button(.cancel, flow.cancel_label"))
        XCTAssertTrue(model.contains("Button(.confirm, flow.confirm_label"))
    }


    func testDialogTargetsParseAndMatchTheirFixtures() throws {
        for state in Self.states {
            let parsed = DialogTarget(flag: state.target.flag)
            XCTAssertEqual(parsed, state.target, state.target.flag)
            XCTAssertEqual(LaunchOptions(arguments: ["--open=\(state.target.flag)"], environment: [:]).open, .dialog(state.target))
            let shell = try shell(state)
            XCTAssertTrue(state.target.matches(shell), "\(state.target.flag) should match \(state.fixture)")
            for other in Self.states where other.target != state.target {
                XCTAssertFalse(other.target.matches(shell), "\(other.target.flag) must not match \(state.fixture)")
            }
        }
        XCTAssertNil(DialogTarget(flag: "reset:idle"))
        XCTAssertNil(DialogTarget(flag: "remove"))
        XCTAssertNil(LaunchOptions(arguments: ["--open=nonsense"], environment: [:]).open)

        XCTAssertEqual(LaunchOptions(arguments: ["--open=rowmenu:3"], environment: [:]).open, .rowMenu(row: 3))
        XCTAssertNil(LaunchOptions(arguments: ["--open=bandmenu"], environment: [:]).open)
    }



    func testConfirmResetIsNeverSentUnlessArmed() throws {
        let review = try exported("reset-review").shell
        XCTAssertFalse(review.reset.is_armed)
        XCTAssertNil(DialogModel.resetConfirmIntent(review.reset))
        let reviewSpec = DialogModel.spec(.reset, shell: review)
        XCTAssertEqual(reviewSpec.button(.confirm)?.enabled, false)
        var focus = DialogModel.FocusModel(reviewSpec)

        XCTAssertEqual(focus.cycle, [.checkbox, .cancel])
        for _ in 0..<4 { focus.tab(); XCTAssertNotEqual(focus.focused, .confirm) }
        XCTAssertFalse([focus.space(), focus.returnKey()].contains(.confirm_reset))

        let armed = try exported("reset-armed").shell
        XCTAssertTrue(armed.reset.is_armed)
        XCTAssertEqual(DialogModel.resetConfirmIntent(armed.reset), .confirm_reset)
        let armedSpec = DialogModel.spec(.reset, shell: armed)
        XCTAssertEqual(armedSpec.button(.confirm)?.enabled, true)
        XCTAssertEqual(armedSpec.button(.confirm)?.intent, .confirm_reset)
        var armedFocus = DialogModel.FocusModel(armedSpec)
        XCTAssertEqual(armedFocus.focused, .cancel)
        armedFocus.tab()
        XCTAssertEqual(armedFocus.focused, .confirm)
        XCTAssertEqual(armedFocus.space(), .confirm_reset)
        XCTAssertNil(armedFocus.returnKey(), "Return never confirms (P-72)")

        armedFocus.tab()
        XCTAssertEqual(armedFocus.focused, .checkbox)
        XCTAssertEqual(armedFocus.space(), .acknowledge_reset)
    }


    func testRetryOnlyWhenTheResetAwaitsReconciliation() throws {
        let retry = try exported("reset-blocked-pending").shell
        XCTAssertEqual(DialogModel.resetRetryIntent(retry.reset), .retry_reset)
        XCTAssertEqual(DialogModel.spec(.reset, shell: retry).buttons.map(\.id), [.cancel, .retry])
        let noCredit = try exported("reset-blocked-no-credit").shell
        XCTAssertNil(DialogModel.resetRetryIntent(noCredit.reset))
        XCTAssertEqual(DialogModel.spec(.reset, shell: noCredit).buttons.map(\.id), [.cancel])
        XCTAssertEqual(DialogModel.spec(.reset, shell: noCredit).button(.cancel)?.label, "Close")
    }



    func testRenameReturnSendsCommitRenameWithTheDraft() throws {
        let shell = try exported("rename-open").shell
        XCTAssertEqual(shell.rename.initial_label, "Codex Personal")
        let draft = "Codex Personal 2"
        let spec = DialogModel.spec(.rename, shell: shell, renameDraft: draft)
        XCTAssertEqual(spec.initialFocus, .field)
        XCTAssertEqual(spec.button(.confirm)?.intent, .commit_rename(label: draft))
        var focus = DialogModel.FocusModel(spec)
        XCTAssertEqual(focus.focused, .field)
        XCTAssertEqual(focus.returnKey(renameDraft: draft), .commit_rename(label: draft))
        focus.tab()
        XCTAssertEqual(focus.focused, .cancel)
        XCTAssertNil(focus.returnKey(renameDraft: draft), "Return outside the field is inert")
        XCTAssertEqual(focus.escape(), .cancel_rename)
    }



    func testRemoveButtonsFollowTheFlowState() throws {
        let plain = try exported("remove-plain-open").shell
        XCTAssertEqual(DialogModel.removeButtons(plain.remove, proxyCanRefresh: true).map { ($0.label, $0.style, $0.enabled) }.map { "\($0.0)|\($0.1)|\($0.2)" },
                       ["Cancel|ghost|true", "Remove|destructive|true"])
        XCTAssertEqual(DialogModel.removeMuted(plain.remove), Copy.removePlainMuted)

        let mapped = try exported("remove-mapped-open").shell
        XCTAssertEqual(DialogModel.removeButtons(mapped.remove, proxyCanRefresh: true).map(\.label), ["Cancel", "Remove"])
        XCTAssertEqual(DialogModel.removeButtons(mapped.remove, proxyCanRefresh: true).last?.intent, .confirm_remove)
        XCTAssertEqual(DialogModel.removeMuted(mapped.remove), Copy.removeMappedMuted)

        let paused = try exported("remove-mapped-pause-requested").shell
        XCTAssertFalse(paused.remove.can_finish)
        let pausedButtons = DialogModel.removeButtons(paused.remove, proxyCanRefresh: paused.proxy_can_refresh)
        XCTAssertEqual(pausedButtons.map(\.label), ["Cancel"])
        XCTAssertEqual(pausedButtons.map(\.enabled), [true])
        XCTAssertEqual(DialogModel.removeButtons(paused.remove, proxyCanRefresh: false).map(\.enabled), [true])

        let finish = try exported("remove-mapped-can-finish").shell
        XCTAssertEqual(DialogModel.removeButtons(finish.remove, proxyCanRefresh: true).map(\.label), ["Cancel"])

    }


    func testOnlyRemovalVerbsAreDestructive() throws {
        for state in Self.states {
            let spec = DialogModel.spec(state.target.kind, shell: try shell(state))
            let red = spec.buttons.filter { $0.style == .destructive }.map(\.label)
            let removePending = try shell(state).remove.pause_requested
            if state.target.kind == .remove && !removePending {
                XCTAssertEqual(red, ["Remove"], state.fixture)
            } else {
                XCTAssertEqual(red, [], state.fixture)
            }
        }
    }



    func testResetScreensAndProjectedLines() throws {
        let review = try exported("reset-review").shell.reset
        XCTAssertEqual(DialogModel.resetScreen(review), .review)
        XCTAssertEqual(DialogModel.resetEvidenceLine(review), "2 available · 73% used · Weekly · next reset 2026-Jul-28 03:00 UTC (in 3d 0h)")
        XCTAssertNil(DialogModel.resetProxyClearLine(review))

        let cleared = try exported("reset-dispatched-settled-cleared").shell.reset
        XCTAssertEqual(DialogModel.resetScreen(cleared), .dispatched)
        XCTAssertEqual(DialogModel.resetProxyClearLine(cleared), "Failover: cooldown cleared.")
        XCTAssertEqual(DialogModel.spec(.reset, shell: try exported("reset-dispatched-settled-cleared").shell).buttons.map { "\($0.label)|\($0.style)" }, ["Close|primary"])

        let unsent = try exported("reset-dispatched-settled-unsent").shell.reset
        XCTAssertNil(DialogModel.resetProxyClearLine(unsent), "no proxy-clear line unless the core shows it")
        XCTAssertTrue(unsent.outcome_text.hasPrefix("This request was not sent after all."))

        let failed = try exported("reset-settled-clear-failed").shell
        XCTAssertEqual(DialogModel.resetProxyClearLine(failed.reset)?.hasPrefix("Failover: cooldown not cleared — "), true)
        XCTAssertEqual(failed.notice.kind, .none, "the core reports the failed clear on the sheet's line, not as a toast (C2 export)")

        let blocked = try exported("reset-blocked-pending").shell.reset
        XCTAssertEqual(DialogModel.resetScreen(blocked), .blocked)
        XCTAssertTrue(blocked.awaits_reconciliation)
        XCTAssertEqual(blocked.blocked_text, "An earlier reset attempt for this account has not settled. Reconcile it first.")
    }






    func testKeyboardModelPerDialog() throws {
        for state in Self.states {
            let shell = try shell(state)
            let spec = DialogModel.spec(state.target.kind, shell: shell, renameDraft: shell.rename.initial_label)
            var focus = DialogModel.FocusModel(spec)
            let initial = try XCTUnwrap(focus.focused, state.fixture)
            XCTAssertEqual(initial, state.target.kind == .rename ? .field : .cancel, "\(state.fixture): initial focus (P-72)")
            XCTAssertTrue(spec.isEnabled(initial), "\(state.fixture): initial focus must be an enabled control")

            var cycle = [initial]
            for _ in 0..<(spec.order.count + 1) {
                focus.tab()
                let next = try XCTUnwrap(focus.focused)
                if next == initial { break }
                cycle.append(next)
            }
            XCTAssertEqual(focus.focused, initial, "\(state.fixture): Tab must cycle back inside the sheet")
            let enabled = spec.order.filter(spec.isEnabled)
            let start = try XCTUnwrap(enabled.firstIndex(of: initial))
            XCTAssertEqual(cycle, Array(enabled[start...] + enabled[..<start]), "\(state.fixture): Tab visits the enabled controls in order")
            focus.shiftTab()
            XCTAssertEqual(focus.focused, cycle.last, "\(state.fixture): Shift-Tab reverses")
            focus.tab()
            XCTAssertEqual(focus.focused, initial)

            let returned = focus.returnKey(renameDraft: shell.rename.initial_label)
            if state.target.kind == .rename {
                XCTAssertEqual(returned, .commit_rename(label: shell.rename.initial_label), state.fixture)
            } else {
                XCTAssertNil(returned, "\(state.fixture): Return never confirms")
            }
            let escaped = focus.escape()
            XCTAssertEqual(escaped, DialogModel.cancelIntent(state.target.kind), state.fixture)
            let spaced = focus.space()
            if state.target.kind != .rename {
                XCTAssertEqual(spaced, DialogModel.cancelIntent(state.target.kind), "\(state.fixture): Space on the focused Cancel/Close cancels")
            }
            let buttons = spec.buttons.map { "\($0.label)\($0.enabled ? "" : "(disabled)")" }.joined(separator: " · ")
            print("KEYLOG \(state.target.flag.padding(toLength: 22, withPad: " ", startingAt: 0)) initial=\(initial) tab=\(cycle.map(\.rawValue).joined(separator: "→"))→\(initial) return=\(returned.map { $0.name } ?? "inert") escape=\(escaped.name) space=\(spaced?.name ?? "inert") buttons=[\(buttons)]")
        }
    }

}
