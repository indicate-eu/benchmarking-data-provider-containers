// This file contains general definitions that are shared between the
// different quality indicators.

library "IndicateQiElements" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

// TODO: @sgibb,: drop default value when leaving testing environment
parameter "Review Period"
    default Interval[@1005-04-05T00:00:00.0, @3025-04-20T00:00:00.0)

// Terminology
// The OMOPSV (OMOP Standard Vocabulary) codesystem is built-in and
// uses the OMOP concept id as code.
codesystem OMOPSV: 'https://fhir-terminology.ohdsi.org' // SV = Standardized Vocabulary

// Visit
code "IcuAdmissionDate": '36659961' from OMOPSV     // Intensive care unit (ICU) admission date
code "IcuDischargeDate": '36659649' from OMOPSV     // Intensive care unit (ICU) discharge date

code "Intensive Care": '32037' from OMOPSV

code "Body Height": '3036277' from OMOPSV

code "Body Weight": '4099154' from OMOPSV

code "Ideal Body Weight": '4062985' from OMOPSV

code "Gender Female": '8532' from OMOPSV
code "Gender Male":   '8507' from OMOPSV

define function "Ideal Body Weight for Height"(Height Quantity, Gender Code):
  (1) _
    let heightPart: 0.91 * (convert Height to 'cm' - 152.4 'cm').value
      return Quantity{
               value: case
                        when Gender ~ "Gender Female" then
                          45.5 + heightPart
                        when Gender ~ "Gender Male" then
                          50 + heightPart
                        else
                          47.75 + heightPart
                      end,
               unit: 'kg'
             }

context Patient

define "Age at Start of Review Period":
  AgeInYearsAt(date from start of "Review Period")

define "Most Recent Body Height Measurement":
  First([Measurement: "Body Height"] m
          return all m
          sort by measurementDatetime desc)

define "Most Recent Body Weight Measurement":
  First([Measurement: "Body Weight"] m
          return all m
          sort by measurementDatetime desc)

define "Most Recent Ideal Body Weight Measurement":
  First([Measurement: "Ideal Body Weight"] m
          return all m
          sort by measurementDatetime desc)

define "Ideal Body Weight Measured or Computed":
  case
    when "Most Recent Ideal Body Weight Measurement" is not null then
      convert "Most Recent Ideal Body Weight Measurement" to Quantity
    when "Most Recent Body Height Measurement" is not null then
      "Ideal Body Weight for Height"("Most Recent Body Height Measurement",
                                     Patient.genderConcept)
    else
      null
  end

/*
@title: Intensive Care Visits
@description: Limit visits to intensive care patients.
@return: Entries with an "Intensive Care" concept.
@author: Sebastian Gibb <mail@sebastiangibb.de>
@examples:
include "IndicateQiElements" called elm
elm."Intensive Care Visits"
*/
define "Intensive Care Visits":
  [VisitOccurrence: "Intensive Care"] v
    where v.visitStartDatetime <= v.visitEndDatetime
    return all v
    sort by visitStartDatetime

/*
@title: Intensive Care Visits in Review Period
@description: Limit visits/population to adult intensive care patients in the
review period.
@return: Entries with an "Intensive Care" concept in the Review Period
@author: Sebastian Gibb <mail@sebastiangibb.de>
@examples:
include "IndicateQiElements" called elm
elm."Intensive Care Visits in Review Period"
*/
define "Intensive Care Visits in Review Period":
  "Intensive Care Visits" v
    where v.visitStartDatetime after start of "Review Period"
      and v.visitEndDatetime before end of "Review Period"
    return all v

/*
@examples
include "IndicateQiElements" called elm
code "Glucose": '3020491' from elm.OMOPSV
elm."Measurements in Review Period" m where m.measurementConcept ~ "Glucose"
*/
define "Measurements in Review Period":
    [Measurement] m
        where m.measurementDatetime in "Review Period"
        return all m

/*
@title: Lenght of stay
@description: Returns the duration of the given visits periods.
@param: vs `List` of time `VisitOccurrence`s defining the visit period.
@return: duration of the visit.
@author: Sebastian Gibb <mail@sebastiangibb.de>
@examples:
include "IndicateQiElements" called elm
elm.LengthOfStay(elm.IntensiveCarePatients)
*/
define function LengthOfStay(vs List<VisitOccurrence>):
    (vs) v return all duration in days between v.visitStartDate and v.visitEndDate

/*
@title: Limit Time Period to Review Period
@description: Restrict time period to the given review period.
@param: tp `List` of time `Interval`s defining the visit/observation period.
@param: rp `Interval` of the review period.
@return: intersection time and review period.
@author: Sebastian Gibb <mail@sebastiangibb.de>
@examples:
include "IndicateQiElements" called elm
define b:
    ({Interval[@1990-01-01, @1990-12-31],
      Interval[@2025-04-05, @2025-04-08],
      Interval[@2025-04-05, @2025-04-18],
      Interval[@2025-04-18, @2025-04-25]})
define rp:
    Interval[@2025-04-05T00:00:00.0, @2025-04-20T00:00:00.0)
elm.LimitPeriod(b, rp)
*/
define function LimitPeriod(tp List<Interval<DateTime>>, rp Interval<DateTime>):
    (tp) p return all p intersect (rp)

define function "Measurements with Neighbors"(measurements List<Measurement>):
  (((Flatten({Tail(measurements), {null}})) m aggregate r
     starting ({minusTwo: null, minusOne: First(measurements), results: {}}):
     {
       minusTwo: r.minusOne,
       minusOne: m,
       results:  Flatten({
                           r.results,
                           {{
                             previous: r.minusTwo,
                             current:  r.minusOne,
                             next:     m
                           }}
                         })
     }).results
     // The weird as List<...> is due to a weakness in the type inference of
     // the CQL engine.
     as List<Tuple{previous Measurement, current Measurement, next Measurement}>)

// Quality Indicator Result Formatting

define function "Period Result"(period                Interval<DateTime>,
                                isInInitialPopulation Boolean,
                                numerator             Integer,
                                denominator           Integer):
  {
    period:      period,
    numerator:   numerator,
    denominator: denominator,
    qi:          if isInInitialPopulation then
                   numerator / denominator
                 else
                   null
  }

define function "Overall Result"(
  patient              Person,
  periodResultsByVisit List<List<Tuple{period      Interval<DateTime>,
                                       numerator   Integer,
                                       denominator Integer,
                                       qi          Decimal}>>
):
  {
    patient:      patient,
    reviewPeriod: "Review Period",
    periods:      Flatten(periodResultsByVisit)
  }
