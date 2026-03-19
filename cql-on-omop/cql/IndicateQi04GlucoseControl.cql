// Name     04 - Glucose Control
// Version  1.0
//
// Description:
//   The blood glucose levels of critically ill patients should be kept
//   within an acceptable range.  Regular measurements, at least once
//   per shift and possibly corrective treatments are required.  The type
//   of treatment differs depending on the type of derangement of blood
//   glucose disorder, and is not included in this quality indicator.
//
// Numerator:
//  (All ICU patients) - (all patients with <= 10 mmol/l glucose )
//  (includes all patients with glucose > 10 mmol/l and all patients without
//  any glucose measurement)
//
// Denominator:
//  All patients admitted to the intensive care unit during
//  the period reviewed.

library "IndicateQi04GlucoseControl" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include TimePeriods called T

parameter "Acceptable Glucose Levels"
  default Interval[3.3 'mmol/L', 10.0 'mmol/L']

parameter "Time between consecutive non-Acceptable Glucose Levels"
  default 2 hours

code "Glucose in Serum (Mass/volume)":                          '3004501' from elm.OMOPSV
code "Glucose in Blood (Mass/volume)":                          '3000483' from elm.OMOPSV
code "Glucose in Venous Blood (Mass/volume)":                   '3033408' from elm.OMOPSV
code "Glucose in Mixed Venous Blood (Mass/volume)":             '1092148' from elm.OMOPSV // TODO(jmoringe): this is no longer in the minimal dataset, why
code "Glucose in Capillary Blood by Glucometer (Mass/volume)":  '3034962' from elm.OMOPSV // TODO(jmoringe): this is no longer in the minimal dataset, why
// Added to minimal dataset:

code "Glucose in Arterial Blood (Mass/volume)":                 '3031266' from elm.OMOPSV

code "Glucose in Capillary Blood (Mass/volume)":                '3004077' from elm.OMOPSV
code "Glucose in Blood (Moles/volume)":                         '3020491' from elm.OMOPSV
code "Glucose in Capillary Blood by Glucometer (Moles/volume)": '3001501' from elm.OMOPSV
code "Glucose in Mixed Venous Blood (Moles/volume)":            '1761753' from elm.OMOPSV
code "Glucose in Serum or Plasma (Moles/volume)":               '3013826' from elm.OMOPSV
code "Glucose in Venous Blood (Moles/volume)":                  '3038515' from elm.OMOPSV

concept "Glucose Level": {
  "Glucose in Serum (Mass/volume)",
  "Glucose in Blood (Mass/volume)",
  "Glucose in Venous Blood (Mass/volume)",
  "Glucose in Mixed Venous Blood (Mass/volume)",
  "Glucose in Capillary Blood by Glucometer (Mass/volume)",
  "Glucose in Arterial Blood (Mass/volume)",
  "Glucose in Capillary Blood (Mass/volume)",
  "Glucose in Blood (Moles/volume)",
  "Glucose in Capillary Blood by Glucometer (Moles/volume)",
  "Glucose in Mixed Venous Blood (Moles/volume)",
  "Glucose in Serum or Plasma (Moles/volume)",
  "Glucose in Venous Blood (Moles/volume)"
}

context Patient

// Glucose Measurements

define "Valid Glucose Measurements":
  [Measurement: "Glucose Level"] m // TODO(moringenj): restrict to review period?
    // Some measurements in the database lack at least one of these properties.
    where not m.valueAsNumber is null and not m.unitConcept is null
    return all m
    sort by measurementDatetime

// Glucose levels

define function "Convert g/L to mol/L"(quantity Quantity):
  (1) _
    let scaled: convert quantity to 'mg/dL'
      return Quantity{value: 1/18 * scaled.value, unit: 'mmol/L'}

define function "Ensure Glucose Level in mol/L"(glucoseLevel Quantity):
  case
    when Matches(glucoseLevel.unit, '.*g/.*L') then
      "Convert g/L to mol/L"(glucoseLevel)
    when Matches(glucoseLevel.unit, '.*mol/.*L') then
      glucoseLevel
    else
      Message(null, true, '400', 'Error', 'Unit is "' + glucoseLevel.unit + '" but must be either "mol/L" or convertible to "g/L"')
  end

define function "Is High Glucose Level"(glucoseLevel Quantity):
  "Ensure Glucose Level in mol/L"(glucoseLevel) > end of "Acceptable Glucose Levels"

define function "Is Low Glucose Level"(glucoseLevel Quantity):
  "Ensure Glucose Level in mol/L"(glucoseLevel) < start of "Acceptable Glucose Levels"

define function "Is Acceptable Glucose Level"(glucoseLevel Quantity):
      (not "Is High Glucose Level"(glucoseLevel))
  and (not "Is Low Glucose Level"(glucoseLevel))

define function "Acceptable Follow-up Glucose Level"(firstValue  Quantity,
                                                     secondValue Quantity):
     "Is Acceptable Glucose Level"(secondValue)
  /* Below acceptable range but increased by at least 20 % */
  or (    "Is Low Glucose Level"(firstValue)
      and "Is Low Glucose Level"(secondValue)
      and secondValue > firstValue * 1.2)
  /* Above acceptable range but decreased by at least 20 % */
  or (    "Is High Glucose Level"(firstValue)
      and "Is High Glucose Level"(secondValue)
      and secondValue < firstValue * 0.8)

define function "Time between Measurements At Most"(earlierMeasurement Measurement,
                                                    laterMeasurement   Measurement,
                                                    maximumTime        Quantity):
  // TODO(moringenj): assert maximumTime is in hours
  (difference in hours between (convert earlierMeasurement to DateTime)
                       and     (convert laterMeasurement   to DateTime))
  <= maximumTime.value

define function "Successful Glucose Control"(previousMeasurement Measurement,
                                             measurement         Measurement,
                                             nextMeasurement     Measurement):
      (   (previousMeasurement is null)
       or "Time between Measurements At Most"(previousMeasurement,
                                              measurement,
                                              10 hours))
  and ("Is Acceptable Glucose Level"(convert measurement to Quantity)
       or (if nextMeasurement is null then
             false
           else
                 "Time between Measurements At Most"(
                   measurement,
                   nextMeasurement,
                   "Time between consecutive non-Acceptable Glucose Levels"
                 )
             and (   "Is Acceptable Glucose Level"(convert nextMeasurement to Quantity)
                  or "Acceptable Follow-up Glucose Level"(
                       convert measurement     to Quantity,
                       convert nextMeasurement to Quantity
                     ))))

define function "Acceptable Glucose Measurements"(measurements List<Tuple{previous Measurement, current Measurement, next Measurement}>,
                                                  isFirstShift Boolean):
  // Do the first triple separately so that we can indicate that the
  // predecessor of the first measurement does not matter if the context is the
  // first shift of an ICU visit.
  Flatten({
    (1) _
      let first: First(measurements)
        return {
          "Successful Glucose Control"(
            if isFirstShift then null else first.previous,
            first.current,
            first.next
          )
        },
    (Tail(measurements)) m
      return all "Successful Glucose Control"(m.previous, m.current, m.next)
  })

define function "Conforming Glucose Measurements"(measurements List<Tuple{previous Measurement, current Measurement, next Measurement}>,
                                                  isFirstShift Boolean):
  if Exists(measurements) then
    AllTrue("Acceptable Glucose Measurements"(measurements, isFirstShift))
  else
    false

// Shifts

define function "Measurements during Shift Plus Neighbors"(shift Interval<DateTime>):
  (1) _
    let measurementsWithNeighbors: (elm."Measurements with Neighbors"("Valid Glucose Measurements")
                                    as List<Tuple{previous Measurement, current Measurement, next Measurement}>)
      return (measurementsWithNeighbors) m
               where (convert m.current to DateTime) during shift
               return all m

define function "Is Conforming Shift"(shift        Interval<DateTime>,
                                      isFirstShift Boolean):
  (1) _
    let shiftMeasurements: "Measurements during Shift Plus Neighbors"(shift)
      return "Conforming Glucose Measurements"(shiftMeasurements, isFirstShift)

define function "Conforming Shifts in Visit"(shifts List<Interval<DateTime>>):
  // Handle the first shift of each ICU visit specially since the
  // first measurement of that first shift does not have a preceding
  // measurement.
  Flatten({({ First(shifts) }) s
              where "Is Conforming Shift"(s, true)
              return all s,
           (Tail(shifts)) s
             where "Is Conforming Shift"(s, false)
             return all s})

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  AgeInYearsAt(convert visit to DateTime) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit),
        shifts:                      T."Shifts during Visit"(visit),
        goodShifts:                  "Conforming Shifts in Visit"(shifts)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodShifts) s where s during period),
                     Count((shifts)     s where (s as Interval<DateTime>) during period)
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
