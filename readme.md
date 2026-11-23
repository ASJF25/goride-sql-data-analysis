# GoRide – Ride-Sharing Data Analysis using PostgreSQL

## Project Overview
This academic project focuses on cleaning, standardising and analysing multi-source ride-sharing data from GoRide and QuickHop using PostgreSQL.

The objective was to address data inconsistencies, investigate duplicate customer records and generate meaningful business insights through SQL queries.

## Tools & Technologies
- PostgreSQL
- SQL
- Data Cleaning
- Data Transformation
- Data Analysis

## Key Data Challenges & Solutions

### 1. Inconsistent Rating Scales
GoRide used a 1–5 rating scale, while QuickHop used a 1–10 scale. I converted QuickHop ratings to a 1–5 scale by dividing them by 2, allowing consistent rating analysis.

### 2. Duplicate Customer Records
Customers appearing on both platforms had different customer IDs. I investigated potential matches using available merge information and phone-number normalisation.

### 3. Inconsistent Trip Statuses
Different status labels were standardised, including:
- `finished` → `completed`
- `aborted` → `cancelled_by_rider`
- `no_show` and `noshow` → a common status

### 4. Payment Data Inconsistencies
I used SQL CASE statements and conditional aggregation to handle service-type corrections and analyse successful payments, refunds and net revenue.

### 5. Zone Name Standardisation
Inconsistent zone names, such as `Prenzlauer-berg`, were standardised to `Prenzlauer Berg`.

## Key Analysis Areas
The project covered 25 SQL analytical tasks, including:

- Customer and driver analysis
- Trip and ride performance
- Revenue and refund analysis
- Payment reconciliation
- Driver ratings and performance
- Vehicle revenue analysis
- Customer spending patterns
- Operational anomaly investigation

## SQL Concepts Used
- JOINs
- Common Table Expressions (CTEs)
- CASE statements
- Aggregate functions
- Conditional aggregation
- GROUP BY and HAVING
- Date and string functions
- Subqueries and EXISTS

## Key Learning Outcomes
- Understanding and handling real-world data inconsistencies
- Standardising data from multiple sources
- Identifying potential duplicate records
- Writing structured SQL queries for business analysis
- Validating results before drawing conclusions

## Project Structure
- `goride_analysis.sql` – SQL queries for the 25 analytical tasks
- `notes.md` – Documentation of data challenges and solutions
- `README.md` – Project overview and documentation

**Project Type:** Academic Project  
**Database:** PostgreSQL