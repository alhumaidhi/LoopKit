//
//  PredictedGlucoseChart.swift
//  LoopUI
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts
import HealthKit
import UIKit

public class PredictedGlucoseChart: GlucoseChart, ChartProviding {

    public private(set) var glucosePoints: [ChartPoint] = [] {
        didSet {
            if let lastDate = glucosePoints.last?.x as? ChartAxisValueDate {
                updateEndDate(lastDate.date)
            }
        }
    }

    /// The chart points for predicted glucose
    public private(set) var predictedGlucosePoints: [ChartPoint] = [] {
        didSet {
            if let lastDate = predictedGlucosePoints.last?.x as? ChartAxisValueDate {
                updateEndDate(lastDate.date)
            }
        }
    }

    /// The chart points for alternate predicted glucose
    public private(set) var alternatePredictedGlucosePoints: [ChartPoint]?

    public var targetGlucoseSchedule: GlucoseRangeSchedule? {
        didSet {
            targetGlucosePoints = []
        }
    }

    public var preMealOverride: TemporaryScheduleOverride? {
        didSet {
            preMealOverrideDurationPoints = []
        }
    }

    public var scheduleOverride: TemporaryScheduleOverride? {
        didSet {
            targetOverrideDurationPoints = []
        }
    }

    private var targetGlucosePoints = [TargetChartBar]()

    private var preMealOverrideDurationPoints: [ChartPoint] = []

    private var targetOverrideDurationPoints: [ChartPoint] = []

    private var glucoseChartCache: ChartPointsTouchHighlightLayerViewCache?

    public private(set) var endDate: Date?

    private var predictedGlucoseSoftBounds: PredictedGlucoseBounds?
    
    private let yAxisStepSizeMGDLOverride: Double?

    /// Sara's Pancreas: when true, the y-axis is fixed (40–300 mg/dL, or 2–18 mmol/L) instead of autoscaling,
    /// so the chart never jumps between refreshes. If any value is above the top, one extra step is added.
    public var usesFixedGlucoseAxis = false

        
    private var maxYAxisSegmentCount: Double {
        // when a glucose value is below the predicted glucose minimum soft bound, allow for more y-axis segments
        return glucoseValueBelowSoftBoundsMinimum() ? 5 : 4
    }
    
    private func updateEndDate(_ date: Date) {
        if endDate == nil || date > endDate! {
            self.endDate = date
        }
    }
    
    public init(predictedGlucoseBounds: PredictedGlucoseBounds? = nil,
                yAxisStepSizeMGDLOverride: Double? = nil) {
        self.predictedGlucoseSoftBounds = predictedGlucoseBounds
        self.yAxisStepSizeMGDLOverride = yAxisStepSizeMGDLOverride
        super.init()
    }
}

extension PredictedGlucoseChart {
    public func didReceiveMemoryWarning() {
        glucosePoints = []
        predictedGlucosePoints = []
        alternatePredictedGlucosePoints = nil
        targetGlucosePoints = [TargetChartBar]()
        targetOverrideDurationPoints = []

        glucoseChartCache = nil
    }

    public func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection) -> Chart
    {
        if targetGlucosePoints.isEmpty, xAxisValues.count > 1, let schedule = targetGlucoseSchedule {

            // TODO: This only considers one override: pre-meal or an active override. ChartPoint.barsForGlucoseRangeSchedule needs to accept list of overridden ranges.
            let potentialOverride = (preMealOverride?.isActive() ?? false) ? preMealOverride : (scheduleOverride?.isActive() ?? false) ? scheduleOverride : nil
            targetGlucosePoints = ChartPoint.barsForGlucoseRangeSchedule(schedule, unit: glucoseUnit, xAxisValues: xAxisValues, considering: potentialOverride)

            var displayedScheduleOverride = scheduleOverride
            if let preMealOverride = preMealOverride, preMealOverride.isActive() {
                preMealOverrideDurationPoints = ChartPoint.pointsForGlucoseRangeScheduleOverride(preMealOverride, unit: glucoseUnit, xAxisValues: xAxisValues)

                if displayedScheduleOverride != nil {
                    if displayedScheduleOverride!.scheduledEndDate > preMealOverride.scheduledEndDate {
                        let start = max(displayedScheduleOverride!.startDate, preMealOverride.scheduledEndDate)
                        displayedScheduleOverride!.scheduledInterval = DateInterval(start: start, end: displayedScheduleOverride!.scheduledEndDate)
                    } else {
                        displayedScheduleOverride = nil
                    }
                }
            } else {
                preMealOverrideDurationPoints = []
            }

            if let override = displayedScheduleOverride, override.isActive() || override.startDate > Date() {
                targetOverrideDurationPoints = ChartPoint.pointsForGlucoseRangeScheduleOverride(override, unit: glucoseUnit, xAxisValues: xAxisValues)
            } else {
                targetOverrideDurationPoints = []
            }
        }
        
        let yAxisValues = determineYAxisValues(axisLabelSettings: axisLabelSettings)
        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // Sara's Pancreas: vertical "now" line separating history from prediction
        let nowLine = ChartNowLine.layer(xAxisLayer: xAxisLayer, yAxisLayer: yAxisLayer, xAxisValues: xAxisValues, yAxisValues: yAxisValues)
        
        // The glucose targets
        let targetFill = colors.glucoseTint.withAlphaComponent(0.2)
        let overrideFill: UIColor = colors.glucoseTint.withAlphaComponent(0.45)
        let fills =
            targetGlucosePoints.map {
                if $0.isOverride {
                    return ChartPointsFill(
                        chartPoints: $0.points,
                        fillColor: overrideFill,
                        createContainerPoints: false)
                } else {
                    return ChartPointsFill(
                        chartPoints: $0.points,
                        fillColor: targetFill,
                        createContainerPoints: false)
                }
            } + [
                ChartPointsFill(
                    chartPoints: preMealOverrideDurationPoints,
                    fillColor: overrideFill,
                    createContainerPoints: false
                ),
                ChartPointsFill(
                    chartPoints: targetOverrideDurationPoints,
                    fillColor: overrideFill,
                    createContainerPoints: false
                )]
        
        let targetsLayer = ChartPointsFillsLayer(
            xAxis: xAxisLayer.axis,
            yAxis: yAxisLayer.axis,
            fills: fills
        )

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)

        // Sara's Pancreas: glucose dots are black (label color), like a CGM app
        let circles = ChartPointsScatterCirclesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: glucosePoints, displayDelay: 0, itemSize: CGSize(width: 5, height: 5), itemFillColor: UIColor.label, optimized: true)

        var alternatePrediction: ChartLayer?

        if let altPoints = alternatePredictedGlucosePoints, altPoints.count > 1 {

            let lineModel = ChartLineModel.predictionLine(points: altPoints, color: colors.glucoseTint, width: 2)

            alternatePrediction = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])
        }

        var prediction: ChartLayer?

        if predictedGlucosePoints.count > 1 {
            // Sara's Pancreas: prediction is a light blue dashed line
            let lineColor = (alternatePrediction == nil) ? PredictedGlucoseChart.predictionLineColor : UIColor.secondaryLabel

            let lineModel = ChartLineModel.predictionLine(
                points: predictedGlucosePoints,
                color: lineColor,
                width: 2
            )

            prediction = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])
        }

        if gestureRecognizer != nil {
            glucoseChartCache = ChartPointsTouchHighlightLayerViewCache(
                xAxisLayer: xAxisLayer,
                yAxisLayer: yAxisLayer,
                axisLabelSettings: axisLabelSettings,
                chartPoints: glucosePoints + (alternatePredictedGlucosePoints ?? predictedGlucosePoints),
                tintColor: colors.glucoseTint,
                gestureRecognizer: gestureRecognizer
            )
        }

        let layers: [ChartLayer?] = [
            gridLayer,
            targetsLayer,
            xAxisLayer,
            yAxisLayer,
            glucoseChartCache?.highlightLayer,
            prediction,
            alternatePrediction,
            nowLine,
            circles
        ]

        return Chart(
            frame: frame,
            innerFrame: innerFrame,
            settings: chartSettings,
            layers: layers.compactMap { $0 }
        )
    }
    
    /// Sara's Pancreas: light blue for the prediction line
    static let predictionLineColor = UIColor(red: 0.36, green: 0.66, blue: 0.90, alpha: 1)

    private func fixedYAxisValues(axisLabelSettings: ChartLabelSettings?) -> [ChartAxisValue] {
        let axisValueGenerator: (Double) -> ChartAxisValue
        if let axisLabelSettings = axisLabelSettings {
            axisValueGenerator = { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }
        } else {
            axisValueGenerator = { ChartAxisValueDouble($0) }
        }

        var steps: [Double]
        let extraStep: Double
        if glucoseUnit == .milligramsPerDeciliter {
            steps = [40, 100, 200, 300]
            extraStep = 400
        } else {
            steps = [2, 6, 10, 14, 18]
            extraStep = 22
        }

        let allValues = [glucosePoints, predictedGlucosePoints, targetGlucosePoints.flatMap { $0.points }].flatMap { $0 }.map { $0.y.scalar }
        if let maxValue = allValues.max(), maxValue > steps.last! {
            steps.append(extraStep)
        }
        if let minValue = allValues.min(), minValue < steps.first! - 2 { // tolerate a CGM "LOW" reading (39 mg/dL)
            steps.insert(0, at: 0)
        }

        return steps.map(axisValueGenerator)
    }

    private func determineYAxisValues(axisLabelSettings: ChartLabelSettings? = nil) -> [ChartAxisValue] {
        if usesFixedGlucoseAxis {
            return fixedYAxisValues(axisLabelSettings: axisLabelSettings)
        }

        let points = [
            glucosePoints, predictedGlucosePoints,
            preMealOverrideDurationPoints, targetOverrideDurationPoints,
            targetGlucosePoints.flatMap { $0.points },
            glucoseDisplayRangePoints
        ].flatMap { $0 }

        let axisValueGenerator: ChartAxisValueStaticGenerator
        if let axisLabelSettings = axisLabelSettings {
            axisValueGenerator = { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) }
        } else {
            axisValueGenerator = { ChartAxisValueDouble($0) }
        }
        
        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesUsingLinearSegmentStep(chartPoints: points,
            minSegmentCount: 2,
            maxSegmentCount: maxYAxisSegmentCount,
            multiple: glucoseUnit == .milligramsPerDeciliter ? (yAxisStepSizeMGDLOverride ?? 25) : 1,
            axisValueGenerator: axisValueGenerator,
            addPaddingSegmentIfEdge: false
        )
        
        return yAxisValues
    }
}

extension PredictedGlucoseChart {
    public func setGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        glucosePoints = glucosePointsFromValues(glucoseValues)
    }

    public func setPredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        let clampedPredicatedGlucoseValues = clampPredictedGlucoseValues(glucoseValues)
        predictedGlucosePoints = glucosePointsFromValues(clampedPredicatedGlucoseValues)
    }

    public func setAlternatePredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) {
        alternatePredictedGlucosePoints = glucosePointsFromValues(glucoseValues)
    }
}


// MARK: - Clamping the predicted glucose values
extension PredictedGlucoseChart {
    var chartMaximumValue: HKQuantity? {
        guard let glucosePointMaximum = glucosePoints.max(by: { point1, point2 in point1.y.scalar < point2.y.scalar }) else {
            return nil
        }
        
        let yAxisValues = determineYAxisValues()
        
        if let maxYAxisValue = yAxisValues.last,
            maxYAxisValue.scalar > glucosePointMaximum.y.scalar
        {
            return HKQuantity(unit: glucoseUnit, doubleValue: maxYAxisValue.scalar)
        }
        
        return HKQuantity(unit: glucoseUnit, doubleValue: glucosePointMaximum.y.scalar)
    }
        
    var chartMinimumValue: HKQuantity? {
        guard let glucosePointMinimum = glucosePoints.min(by: { point1, point2 in point1.y.scalar < point2.y.scalar }) else {
            return nil
        }
        
        let yAxisValues = determineYAxisValues()
        
        if let minYAxisValue = yAxisValues.first,
            minYAxisValue.scalar < glucosePointMinimum.y.scalar
        {
            return HKQuantity(unit: glucoseUnit, doubleValue: minYAxisValue.scalar)
        }
        
        return HKQuantity(unit: glucoseUnit, doubleValue: glucosePointMinimum.y.scalar)
    }
    
    func clampPredictedGlucoseValues(_ glucoseValues: [GlucoseValue]) -> [GlucoseValue] {
        guard let predictedGlucoseBounds = predictedGlucoseSoftBounds else {
            return glucoseValues
        }
        
        let predictedGlucoseValueMaximum = chartMaximumValue != nil ? max(predictedGlucoseBounds.maximum, chartMaximumValue!) : predictedGlucoseBounds.maximum
        
        let predictedGlucoseValueMinimum = chartMinimumValue != nil ? min(predictedGlucoseBounds.minimum, chartMinimumValue!) : predictedGlucoseBounds.minimum
        
        return glucoseValues.map {
            if $0.quantity > predictedGlucoseValueMaximum {
                return PredictedGlucoseValue(startDate: $0.startDate, quantity: predictedGlucoseValueMaximum)
            } else if $0.quantity < predictedGlucoseValueMinimum {
                return PredictedGlucoseValue(startDate: $0.startDate, quantity: predictedGlucoseValueMinimum)
            } else {
                return $0
            }
        }
    }
    
    var chartedGlucoseValueMinimum: HKQuantity? {
        guard let glucosePointMinimum = glucosePoints.min(by: { point1, point2 in point1.y.scalar < point2.y.scalar }) else {
            return nil
        }
        
        return HKQuantity(unit: glucoseUnit, doubleValue: glucosePointMinimum.y.scalar)
    }
    
    func glucoseValueBelowSoftBoundsMinimum() -> Bool {
        guard let predictedGlucoseSoftBounds = predictedGlucoseSoftBounds,
            let chartedGlucoseValueMinimum = chartedGlucoseValueMinimum else
        {
            return false
        }
            
        return chartedGlucoseValueMinimum < predictedGlucoseSoftBounds.minimum
    }
    
    public struct PredictedGlucoseBounds {
        var minimum: HKQuantity
        var maximum: HKQuantity
        
        public static var `default`: PredictedGlucoseBounds {
            return PredictedGlucoseBounds(minimum: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 40),
                                          maximum: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 400))
        }
    }
}
