CREATE TABLE mahasiswa (
	nim SERIAL PRIMARY KEY,
	nama VARCHAR(100) NOT NULL,
	umur INTEGER NOT NULL,
	fakultas VARCHAR(5) NOT NULL,
	tinggi REAL,
	tugas INTEGER,
	ujian INTEGER,
	deskripsi TEXT
);
