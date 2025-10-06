SELECT * FROM ncr_ride_bookings;

SELECT count(*) FROM ncr_ride_bookings
WHERE "Avg VTAT" = NULL;

SELECT count(*) FROM ncr_ride_bookings
WHERE "Avg VTAT" = 'null';

UPDATE ncr_ride_bookings
SET "Cancelled Rides by Customer" = NULL
WHERE "Cancelled Rides by Customer" ILIKE 'null';

UPDATE ncr_ride_bookings SET "Cancelled Rides by Customer" = NULL WHERE "Cancelled Rides by Customer" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Reason for cancelling by Customer" = NULL WHERE "Reason for cancelling by Customer" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Cancelled Rides by Driver" = NULL WHERE "Cancelled Rides by Driver" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Driver Cancellation Reason" = NULL WHERE "Driver Cancellation Reason" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Incomplete Rides" = NULL WHERE "Incomplete Rides" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Incomplete Rides Reason" = NULL WHERE "Incomplete Rides Reason"  ILIKE 'null';
UPDATE ncr_ride_bookings SET "Booking Value" = NULL WHERE "Booking Value" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Ride Distance" = NULL WHERE "Ride Distance" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Driver Ratings" = NULL WHERE "Driver Ratings" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Customer Rating" = NULL WHERE "Customer Rating" ILIKE 'null';
UPDATE ncr_ride_bookings SET "Payment Method" = NULL WHERE "Payment Method" ILIKE 'null';

SELECT * FROM ncr_ride_bookings;

SELECT count(*) FROM ncr_ride_bookings
WHERE "Avg VTAT" = 'null';