import pool from "../config/db.js";

export const getStudents = async (_req, res) => {
  try {
    const result = await pool.query("SELECT * FROM students ORDER BY id DESC");
    res.status(200).json(result.rows);
  } catch (error) {
    console.error("Database error while fetching students:", error);
    res.status(500).json({ message: "Failed to fetch students" });
  }
};

export const createStudent = async (req, res) => {
  let client;

  try {
    const { name, roll, department, year } = req.body;

    if (
      typeof name !== "string" || !name.trim() ||
      typeof roll !== "string" || !roll.trim() ||
      !department || year === undefined || year === ""
    ) {
      return res.status(400).json({
        message: "Name, roll, department, and year are required",
      });
    }

    const allowedDepartments = ["CSE", "EEE", "ECE"];
    if (!allowedDepartments.includes(department)) {
      return res.status(400).json({
        message: "Department must be CSE, EEE, or ECE",
      });
    }

    const studentYear = Number(year);
    if (!Number.isInteger(studentYear) || studentYear < 1900 || studentYear > 2100) {
      return res.status(400).json({ message: "Year must be between 1900 and 2100" });
    }

    const normalizedRoll = roll.trim();
    client = await pool.connect();
    await client.query("BEGIN");
    await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [normalizedRoll]);

    const existing = await client.query(
      "SELECT 1 FROM students WHERE roll = $1 LIMIT 1",
      [normalizedRoll],
    );
    if (existing.rowCount > 0) {
      await client.query("ROLLBACK");
      return res.status(409).json({ message: "This roll number is already registered" });
    }

    const result = await client.query(
      `INSERT INTO students (name, roll, department, year)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [name.trim(), normalizedRoll, department, studentYear],
    );

    await client.query("COMMIT");
    res.status(201).json(result.rows[0]);
  } catch (error) {
    if (client) {
      try {
        await client.query("ROLLBACK");
      } catch {
        // The transaction may already have been rolled back or committed.
      }
    }

    if (error.code === "23505" && error.constraint === "students_roll_unique_idx") {
      return res.status(409).json({ message: "This roll number is already registered" });
    }

    console.error("Database error while registering student:", error);
    res.status(500).json({ message: "Failed to register student" });
  } finally {
    client?.release();
  }
};

export const deleteStudent = async (req, res) => {
  try {
    const studentId = Number(req.params.id);
    if (!Number.isInteger(studentId)) {
      return res.status(400).json({ message: "Invalid student ID" });
    }

    const result = await pool.query(
      "DELETE FROM students WHERE id = $1 RETURNING *",
      [studentId],
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ message: "Student not found" });
    }

    res.status(200).json({
      message: "Student deleted successfully",
      student: result.rows[0],
    });
  } catch (error) {
    console.error("Database error while deleting student:", error);
    res.status(500).json({ message: "Failed to delete student" });
  }
};
