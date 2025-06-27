# Time Series Chart Feature

This feature adds a new time-series graph view to the Vice Tracker app.

## Features

- **Bottom Navigation**: The homepage now has a bottom navigation bar with two tabs:
  - "Daily View": Shows the existing radar chart for a single day
  - "Time Series": Shows the new time-series chart with multiple time scales

## Time Scales

The time-series chart supports multiple time scales:

1. **Day (Hourly)**: Shows vice activities hour by hour for the selected day
2. **Week (Daily)**: Shows vice activities day by day for the week containing the selected date
3. **Month (Daily)**: Shows vice activities day by day for the month of the selected date
4. **Quarter (Weekly)**: Shows vice activities week by week for the quarter containing the selected date
5. **Year (Monthly)**: Shows vice activities month by month for the year of the selected date

## Chart Features

- **Multiple Lines**: Each vice is represented as a separate colored line
- **Legend**: Color-coded legend shows which line corresponds to which vice
- **Interactive**: Charts are built using fl_chart for smooth interaction
- **Responsive**: Chart adapts to different screen sizes and data ranges

## Data Aggregation

- **Hourly**: Aggregates activities within the same hour
- **Daily**: Aggregates activities within the same day  
- **Weekly**: Aggregates activities within the same week (ISO 8601 week calculation)
- **Monthly**: Aggregates activities within the same month

## Usage

1. Open the app and navigate to the homepage
2. Use the bottom navigation to switch between "Daily View" and "Time Series"
3. In the Time Series view, use the dropdown to select your desired time scale
4. The chart will automatically update to show data for the selected scale
5. Use the existing date navigation (arrows, dropdown, "Jump to Today") to change the reference date

The selected date serves as the anchor point for determining which time period to display (e.g., which week, month, quarter, or year to show).