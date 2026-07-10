// This file contains general definitions of domain concepts
// (i.e. clinical) that are shared between the different quality
// indicators.  For shared technical definitions, see IndicateQiUtilities.cql.

library "IndicateQiElements" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

include IndicateQiUtilities called U

// TODO: @sgibb,: drop default value when leaving testing environment
parameter "Review Period"
    default Interval[@1005-04-05T00:00:00.0, @3025-04-20T00:00:00.0)

// Terminology
// The OMOPSV (OMOP Standard Vocabulary) codesystem is built-in and
// uses the OMOP concept id as code.
// SV = Standardized Vocabulary
// In the hierarchical variant, each concept designates the sets of
// its ancestors (which includes the concept itself).
codesystem OMOPSV: 'https://fhir-terminology.ohdsi.org'
codesystem "OMOPSV Hierarchy": 'https://fhir-terminology.ohdsi.org?hierarchical'

// Visit

code "Intensive Care": '32037' from OMOPSV

code "Intubation Tube": '4097216' from "OMOPSV Hierarchy"

code "Body Height": '3036277' from OMOPSV

code "Body Weight": '4099154' from OMOPSV

code "Ideal Body Weight": '4062985' from OMOPSV

code "Gender Female": '8532' from OMOPSV
code "Gender Male":   '8507' from OMOPSV

define function "Ideal Body Weight for Height"(Height Quantity, Gender Code):
  (1) _
    let heightInCM: U.EnsureQuantityWithUnit('Body height', Height, 'cm'),
        heightPart: 0.91 * (heightInCM - 152.4 'cm').value
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

define "Body Height Measurements":
  [Measurement: "Body Height"] m
    return all m
    sort by measurementDatetime desc

define function "Most Recent Body Height Measurement Before"(targetTime DateTime):
  First(("Body Height Measurements") m
          where (targetTime is null) or (convert m to DateTime) before targetTime
          return all m)

define "Body Weight Measurements":
  [Measurement: "Body Weight"] m
    return all m
    sort by measurementDatetime desc

define function "Most Recent Body Weight Measurement Before"(targetTime DateTime):
  First(("Body Weight Measurements") m
          where (targetTime is null) or (convert m to DateTime) before targetTime
          return all m)

define "Ideal Body Weight Measurements":
  [Measurement: "Ideal Body Weight"] m
    return all m
    sort by measurementDatetime desc

define function "Most Recent Ideal Body Weight Measurement Before"(targetTime DateTime):
  First(("Ideal Body Weight Measurements") m
          where (targetTime is null) or (convert m to DateTime) before targetTime
          return all m)

define function "Ideal Body Weight Measured or Computed Before"(targetTime DateTime):
  (1) _
    let idealBodyWeight: "Most Recent Ideal Body Weight Measurement Before"(targetTime),
        bodyHeight:      "Most Recent Body Height Measurement Before"(targetTime)
      return case
               when idealBodyWeight is not null then
                 U.EnsureQuantity('Ideal body weight', idealBodyWeight)
               when bodyHeight is not null then
                 "Ideal Body Weight for Height"(
                   U.EnsureQuantity('Body height', bodyHeight),
                   Patient.genderConcept
                 )
               else
                 null
             end

// This function returns the body mass index as a quantity that is scaled
// and/or converted to 'kg/m^2', not just of any mass/length^2 dimensions.
define function "Body Mass Index Before"(targetTime DateTime):
  (1) _
    let bodyWeight: "Most Recent Body Weight Measurement Before"(targetTime),
        bodyHeight: "Most Recent Body Height Measurement Before"(targetTime)
      return if bodyWeight is not null and bodyHeight is not null then
               (1) __
                 let bodyWeightInKg: U.EnsureQuantityWithUnit('Body weight', bodyWeight, 'kg'),
                     bodyHeightInM:  U.EnsureQuantityWithUnit('Body height', bodyHeight, 'm')
                   // We use multiplication because the CQL Power operator
                   // cannot be applied to quantities.
                   return bodyWeightInKg / (bodyHeightInM * bodyHeightInM)
             else
               null

/*
@title: Intensive Care Visits
@description: Limit visits to intensive care patients.
@return: Entries with an "Intensive Care" concept.
@author: Sebastian Gibb <mail@sebastiangibb.de>
@examples:
include "IndicateQiElements" called elm
elm."Intensive Care Visits"
*/
define "Intensive Care Visit Occurrences":
  [VisitOccurrence: "Intensive Care"] v
    where v.visitStartDatetime < v.visitEndDatetime
    return all convert v to Interval<DateTime>
    sort by low

define "Intensive Care Visit Details":
  [VisitDetail: "Intensive Care"] v
    where v.visitDetailStartDatetime < v.visitDetailEndDatetime
    return all convert v to Interval<DateTime>
    sort by low

define "Intensive Care Visits":
  (1) _
    let allVisitsNotOrdered: Flatten({ "Intensive Care Visit Occurrences",
                                       "Intensive Care Visit Details" }),
        allVisitsOrdered:    (allVisitsNotOrdered) v sort by low
      return collapse(allVisitsOrdered)

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
    where v during "Review Period"
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
