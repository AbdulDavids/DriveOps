//
//  MetricSample.swift
//  DriveOps
//

import Foundation

struct MetricSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}
