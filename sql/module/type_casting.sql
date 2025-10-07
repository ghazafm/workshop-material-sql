ALTER TABLE ncr_ride_bookings
  ALTER COLUMN "Date"  							          TYPE date 		    USING "Date"::date,
  ALTER COLUMN "Time"  							          TYPE time   		  USING "Time"::time,
  ALTER COLUMN "Avg VTAT" 						        TYPE numeric(5,2)	USING ("Avg VTAT")::numeric(5,2),
  ALTER COLUMN "Avg CTAT" 						        TYPE numeric(5,2)	USING ("Avg CTAT")::numeric(5,2),
  ALTER COLUMN "Cancelled Rides by Customer"	TYPE smallint 		USING ("Cancelled Rides by Customer")::smallint,
  ALTER COLUMN "Cancelled Rides by Driver"   	TYPE smallint 		USING ("Cancelled Rides by Driver")::smallint,
  ALTER COLUMN "Incomplete Rides"            	TYPE smallint 		USING ("Incomplete Rides")::smallint,
  ALTER COLUMN "Booking Value"               	TYPE integer  		USING ("Booking Value")::integer,
  ALTER COLUMN "Ride Distance"               	TYPE numeric(5,2) USING ("Ride Distance")::numeric(5,2),
  ALTER COLUMN "Driver Ratings"              	TYPE numeric(2,1) USING ("Driver Ratings")::numeric(2,1),
  ALTER COLUMN "Customer Rating"             	TYPE numeric(2,1) USING ("Customer Rating")::numeric(2,1);
