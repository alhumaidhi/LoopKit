//
//  ChartNowLine.swift
//  LoopKitUI
//
//  Sara's Pancreas customization: a vertical line marking the current time on every chart,
//  separating history (left) from predictions (right).
//

import UIKit
import SwiftCharts

enum ChartNowLine {
    /// Dark gray, close to black but not black, so it reads as a marker rather than data.
    static let color = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.80, alpha: 1)
            : UIColor(white: 0.25, alpha: 1)
    }

    static let width: CGFloat = 1.5

    /// Builds a vertical line layer at the current time spanning the full y-axis range.
    /// Returns nil when the y-axis has fewer than two values (nothing to span) or "now" is outside the x-axis range.
    static func layer(xAxisLayer: ChartAxisLayer, yAxisLayer: ChartAxisLayer, xAxisValues: [ChartAxisValue], yAxisValues: [ChartAxisValue], now: Date = Date()) -> ChartLayer? {
        guard let minY = yAxisValues.first?.scalar, let maxY = yAxisValues.last?.scalar, minY < maxY else {
            return nil
        }
        guard let minX = xAxisValues.first?.scalar, let maxX = xAxisValues.last?.scalar else {
            return nil
        }
        let nowScalar = now.timeIntervalSince1970
        guard nowScalar >= minX, nowScalar <= maxX else {
            return nil
        }

        let formatter = DateFormatter(timeStyle: .short)
        let nowXValue = ChartAxisValueDate(date: now, formatter: formatter)
        let points = [
            ChartPoint(x: nowXValue, y: ChartAxisValueDouble(minY)),
            ChartPoint(x: nowXValue, y: ChartAxisValueDouble(maxY))
        ]
        let model = ChartLineModel(chartPoints: points, lineColor: color, lineWidth: width, animDuration: 0, animDelay: 0, dashPattern: nil)
        return ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [model])
    }
}
