package com.claude.ingestor.analytics;

/**
 * Standard (non-batch, non-cached) input/output pricing for one model, in
 * USD per million tokens.
 */
public record ModelPrice(double inputPerMillion, double outputPerMillion) {
}