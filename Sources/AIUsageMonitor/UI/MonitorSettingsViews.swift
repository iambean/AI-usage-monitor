import SwiftUI

struct MonitorGeneralSettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var confirmClear = false

  var body: some View {
    Form {
      Section(L10n.text("monitor.menuBarSelection", "菜单栏关注项")) {
        ForEach(model.providerStates) { state in
          Picker(
            state.name,
            selection: Binding(
              get: { model.preferences.selectedMetrics[state.id.rawValue] ?? "" },
              set: { value in
                model.updatePreferences { $0.selectedMetrics[state.id.rawValue] = value }
              }
            )
          ) {
            Text(L10n.text("monitor.automaticWindow", "自动选择默认窗口")).tag("")
            ForEach(state.displayMetrics) { metric in
              Text(UsagePresentation.caption(metric, providerID: state.id)).tag(metric.id)
            }
            if let selected = model.preferences.selectedMetrics[state.id.rawValue],
              !selected.isEmpty,
              !state.metrics.contains(where: { $0.id == selected })
            {
              Text(L10n.text("monitor.windowUnavailable", "窗口暂不可用")).tag(selected)
            }
          }
        }
        Text(L10n.text("monitor.menuBarSelectionNote", "数据源中的星标决定菜单栏服务；这里选择它展示的窗口。"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("monitor.appearance", "显示")) {
        Toggle(L10n.text("monitor.compact", "紧凑布局"), isOn: preference(\.compact))
        Picker(L10n.text("monitor.appearance", "显示"), selection: preference(\.appearance)) {
          Text(L10n.text("settings.language.system", "跟随系统")).tag("system")
          Text(L10n.text("monitor.light", "浅色")).tag("light")
          Text(L10n.text("monitor.dark", "深色")).tag("dark")
        }
      }
      Section(L10n.text("monitor.refreshPolicy", "刷新与可靠性")) {
        Toggle(L10n.text("monitor.wakeRefresh", "唤醒后检查所有显示项"), isOn: preference(\.refreshAfterWake))
        Toggle(
          L10n.text("monitor.lowPowerRefresh", "低电量时降低后台刷新频率"), isOn: preference(\.reduceInLowPower)
        )
        Text(L10n.text("monitor.refreshPolicyNote", "打开面板时刷新；重复请求合并，失败后延迟重试，短暂断网显示上次数据。"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("monitor.localHistory", "本地历史")) {
        Picker(L10n.text("monitor.retention", "保留记录"), selection: preference(\.retentionDays)) {
          ForEach([7, 30, 90], id: \.self) { days in
            Text(L10n.format("usage.days", "%d 天", days)).tag(days)
          }
        }
        Toggle(L10n.text("monitor.showForecast", "显示用量估算"), isOn: preference(\.showForecast))
        Text(L10n.text("monitor.retentionNote", "最多保存 10,000 条采样。延长保留期限不会恢复已经清理的记录。"))
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          Button(L10n.text("monitor.exportHistory", "导出 CSV")) { model.exportHistory() }
          Button(L10n.text("monitor.clearHistory", "清除记录…")) { confirmClear = true }
        }
        if let message = model.historyMessage {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .padding(12)
    .alert(L10n.text("monitor.clearHistoryTitle", "清除本机历史记录？"), isPresented: $confirmClear) {
      Button(L10n.text("common.cancel", "取消"), role: .cancel) {}
      Button(L10n.text("monitor.clear", "清除"), role: .destructive) { model.clearHistory() }
    } message: {
      Text(L10n.text("monitor.clearHistoryBody", "此操作不能撤销，不影响服务端用量。之后成功刷新会重新记录。"))
    }
  }

  private func preference<Value>(_ keyPath: WritableKeyPath<MonitorPreferences, Value>) -> Binding<
    Value
  > {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in
        model.updatePreferences { $0[keyPath: keyPath] = value }
      })
  }
}

struct MonitorNotificationSettingsView: View {
  @EnvironmentObject private var model: AppModel
  @State private var selectedKey = ""

  private var choices: [(key: String, title: String, metric: UsageMetric)] {
    model.providerStates.flatMap { state in
      state.metrics.filter { $0.value.availableFraction != nil || $0.value.kind == .balance }.map {
        metric in
        (
          MonitorPreferences.metricKey(providerID: state.id, metricID: metric.id),
          state.name + " · " + UsagePresentation.caption(metric, providerID: state.id), metric
        )
      }
    }
  }
  private var activeKey: String {
    choices.contains { $0.key == selectedKey } ? selectedKey : choices.first?.key ?? ""
  }
  private var isBalance: Bool {
    choices.first { $0.key == activeKey }?.metric.value.kind == .balance
  }

  var body: some View {
    Form {
      Section {
        Toggle(
          L10n.text("monitor.enableNotifications", "启用系统通知"),
          isOn: Binding(
            get: { model.preferences.notificationsEnabled }, set: model.setNotificationsEnabled))
        if let message = model.notificationMessage {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
      }
      Section(L10n.text("monitor.windowAlerts", "窗口提醒")) {
        if choices.isEmpty {
          Text(L10n.text("monitor.noAlertWindows", "成功读取用量后，即可配置对应窗口。"))
        } else {
          Picker(
            L10n.text("monitor.alertTarget", "提醒对象"),
            selection: Binding(
              get: { activeKey }, set: { selectedKey = $0 }
            )
          ) {
            ForEach(choices, id: \.key) { choice in Text(choice.title).tag(choice.key) }
          }
          Toggle(L10n.text("monitor.lowUsageAlert", "额度或余额不足时提醒"), isOn: rule(\.enabled))
          if isBalance {
            HStack {
              Text(L10n.text("monitor.balanceBelow", "余额低于"))
              TextField("", value: rule(\.balanceThreshold), format: .number)
                .frame(width: 90)
              Text(choices.first { $0.key == activeKey }?.metric.value.currency ?? "")
            }
          } else {
            HStack {
              Text(L10n.text("monitor.thresholds", "剩余额度阈值"))
              ForEach([20.0, 10.0, 5.0], id: \.self) { threshold in
                Toggle(
                  "\(Int(threshold))%",
                  isOn: Binding(
                    get: { currentRule.thresholds.contains(threshold) },
                    set: { enabled in
                      updateRule { rule in
                        rule.thresholds.removeAll { $0 == threshold }
                        if enabled { rule.thresholds.append(threshold) }
                      }
                    }
                  )
                ).toggleStyle(.checkbox)
              }
            }
          }
          Toggle(L10n.text("monitor.recoveryAlert", "额度恢复后提醒"), isOn: rule(\.notifyRecovery))
        }
      }
      Section(L10n.text("monitor.resetExpiryAlerts", "Codex 重置到期提醒")) {
        HStack {
          ForEach([3, 1], id: \.self) { days in
            Toggle(
              L10n.format("monitor.daysBefore", "提前 %d 天", days),
              isOn: Binding(
                get: { model.preferences.expiryReminderDays.contains(days) },
                set: { enabled in
                  model.updatePreferences { preferences in
                    preferences.expiryReminderDays.removeAll { $0 == days }
                    if enabled { preferences.expiryReminderDays.append(days) }
                  }
                }
              )
            ).toggleStyle(.checkbox)
          }
        }
      }
      Section(L10n.text("monitor.quietHours", "减少打扰")) {
        Toggle(L10n.text("monitor.quietEnabled", "启用静默时段"), isOn: preference(\.quietHoursEnabled))
        if model.preferences.quietHoursEnabled {
          HStack {
            Picker(L10n.text("monitor.quietStart", "开始"), selection: preference(\.quietStartHour)) {
              ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
            }
            Picker(L10n.text("monitor.quietEnd", "结束"), selection: preference(\.quietEndHour)) {
              ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
            }
          }
        }
        Text(L10n.text("monitor.notificationDedup", "同一阈值每轮提醒一次；同一服务的提醒合并发送。起止时间相同表示全天静默。"))
          .font(.caption).foregroundStyle(.secondary)
        if let until = model.preferences.snoozedUntil, until > Date() {
          Text(L10n.format("monitor.snoozedUntil", "已暂停至 %@", UsagePresentation.fullDate(until)))
            .font(.caption)
          Button(L10n.text("monitor.resumeAlerts", "恢复提醒")) {
            model.updatePreferences { $0.snoozedUntil = nil }
          }
        }
        Button(L10n.text("monitor.previewAlert", "发送预览通知")) { model.previewNotification() }
      }
    }
    .formStyle(.grouped)
    .padding(12)
  }

  private var currentRule: UsageAlertRule {
    model.preferences.alertRules[activeKey] ?? UsageAlertRule()
  }
  private func updateRule(_ update: (inout UsageAlertRule) -> Void) {
    guard !activeKey.isEmpty else { return }
    let key = activeKey
    model.updatePreferences { preferences in
      var value = preferences.alertRules[key] ?? UsageAlertRule()
      update(&value)
      value.balanceThreshold = value.balanceThreshold.isFinite ? max(0, value.balanceThreshold) : 10
      preferences.alertRules[key] = value
    }
  }
  private func rule<Value>(_ keyPath: WritableKeyPath<UsageAlertRule, Value>) -> Binding<Value> {
    Binding(
      get: { currentRule[keyPath: keyPath] },
      set: { value in updateRule { $0[keyPath: keyPath] = value } })
  }
  private func preference<Value>(_ keyPath: WritableKeyPath<MonitorPreferences, Value>) -> Binding<
    Value
  > {
    Binding(
      get: { model.preferences[keyPath: keyPath] },
      set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } })
  }
}
