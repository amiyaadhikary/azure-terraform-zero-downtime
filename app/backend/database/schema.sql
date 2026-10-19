CREATE TABLE IF NOT EXISTS students (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    roll VARCHAR(30) NOT NULL,
    department VARCHAR(10) NOT NULL
        CHECK (department IN ('CSE', 'EEE', 'ECE')),
    year INTEGER NOT NULL
        CHECK (year BETWEEN 1900 AND 2100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Also applies to databases where the students table already exists.
CREATE UNIQUE INDEX IF NOT EXISTS students_roll_unique_idx
    ON students (roll);
