package de.arbeitszeitrechner.calc

import de.arbeitszeitrechner.model.AppSettings
import de.arbeitszeitrechner.model.BreakRule
import org.junit.Assert.assertEquals
import org.junit.Test

class BreakCalculatorTest {

    private val gradual = AppSettings(gradualDeduction = true)
    private val flat = AppSettings(gradualDeduction = false)

    private fun h(hours: Int, minutes: Int = 0) = hours * 60 + minutes

    @Test
    fun noBreakUpToSixHours() {
        assertEquals(0, BreakCalculator.requiredBreak(h(5, 59), gradual))
        assertEquals(0, BreakCalculator.requiredBreak(h(6), gradual))
        assertEquals(0, BreakCalculator.requiredBreak(h(6), flat))
    }

    @Test
    fun gradualDeductionKeepsSixHours() {
        assertEquals(15, BreakCalculator.requiredBreak(h(6, 15), gradual))
        assertEquals(30, BreakCalculator.requiredBreak(h(6, 30), gradual))
        assertEquals(30, BreakCalculator.requiredBreak(h(6, 45), gradual))
    }

    @Test
    fun gradualDeductionAroundNineHours() {
        assertEquals(30, BreakCalculator.requiredBreak(h(9, 30), gradual))
        assertEquals(40, BreakCalculator.requiredBreak(h(9, 40), gradual))
        assertEquals(45, BreakCalculator.requiredBreak(h(9, 45), gradual))
        assertEquals(45, BreakCalculator.requiredBreak(h(11), gradual))
    }

    @Test
    fun flatDeduction() {
        assertEquals(30, BreakCalculator.requiredBreak(h(6, 1), flat))
        assertEquals(30, BreakCalculator.requiredBreak(h(9), flat))
        assertEquals(45, BreakCalculator.requiredBreak(h(9, 1), flat))
    }

    @Test
    fun manualBreakIsUsedWhenLonger() {
        assertEquals(60, BreakCalculator.deductedBreak(h(8, 30), 60, gradual))
        assertEquals(30, BreakCalculator.deductedBreak(h(8, 30), 10, gradual))
    }

    @Test
    fun breakNeverExceedsAttendance() {
        assertEquals(20, BreakCalculator.deductedBreak(20, 45, gradual))
    }

    @Test
    fun autoBreakCanBeDisabled() {
        val off = AppSettings(autoBreak = false)
        assertEquals(0, BreakCalculator.deductedBreak(h(10), 0, off))
        assertEquals(15, BreakCalculator.deductedBreak(h(10), 15, off))
    }

    @Test
    fun customRules() {
        val custom = AppSettings(breakRules = listOf(BreakRule(h(5), 20), BreakRule(h(9), 0)))
        assertEquals(20, BreakCalculator.requiredBreak(h(10), custom))
    }
}
