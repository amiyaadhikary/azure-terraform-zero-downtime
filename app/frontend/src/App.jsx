import React, { useEffect, useState } from "react";
import {
  GraduationCap,
  UserPlus,
  Trash2,
  Users,
  CheckCircle2,
} from "lucide-react";

const API_BASE_URL = (
  import.meta.env.VITE_API_URL ??
  (import.meta.env.PROD ? "" : "http://localhost:5000")
).replace(/\/$/, "");
const API_URL = `${API_BASE_URL}/api/students`;

const emptyForm = {
  name: "",
  roll: "",
  department: "",
  year: "",
};

function App() {
  const [form, setForm] = useState(emptyForm);
  const [students, setStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [deletingId, setDeletingId] = useState(null);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  // Load all students
  const loadStudents = async () => {
    try {
      setLoading(true);
      setError("");

      const response = await fetch(API_URL);

      if (!response.ok) {
        throw new Error("Unable to load students");
      }

      const data = await response.json();
      setStudents(data);
    } catch (err) {
      setError(
        "Could not connect to the server. Make sure the backend is running."
      );
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadStudents();
  }, []);

  // Handle form input
  const handleChange = (event) => {
    const { name, value } = event.target;

    setForm((current) => ({
      ...current,
      [name]: value,
    }));

    setError("");
    setSuccess("");
  };

  // Register student
  const handleSubmit = async (event) => {
    event.preventDefault();

    if (
      !form.name.trim() ||
      !form.roll.trim() ||
      !form.department ||
      !form.year
    ) {
      setError("Please complete all fields.");
      setSuccess("");
      return;
    }

    try {
      setSubmitting(true);
      setError("");
      setSuccess("");

      const response = await fetch(API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: form.name.trim(),
          roll: form.roll.trim(),
          department: form.department,
          year: Number(form.year),
        }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || "Registration failed");
      }

      // PostgreSQL returns id
      setStudents((current) => [data, ...current]);

      setForm(emptyForm);

      setSuccess("Student registered successfully.");
    } catch (err) {
      setError(err.message || "Registration failed.");
      setSuccess("");
    } finally {
      setSubmitting(false);
    }
  };

  // Delete student
  const handleDelete = async (id) => {
    try {
      setDeletingId(id);
      setError("");
      setSuccess("");

      const response = await fetch(`${API_URL}/${id}`, {
        method: "DELETE",
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || "Delete failed");
      }

      // PostgreSQL uses id, NOT _id
      setStudents((current) =>
        current.filter((student) => student.id !== id)
      );

      setSuccess("Student deleted successfully.");
    } catch (err) {
      setError(err.message || "Could not delete the student.");
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <div className="app-shell">
      {/* Header */}
      <header className="topbar">
        <div className="brand">
          <div className="brand-icon">
            <GraduationCap size={21} strokeWidth={2.2} />
          </div>

          <div>
            <h1>Student Registration</h1>
            <p>Student Management System</p>
          </div>
        </div>

        <div className="student-count">
          <Users size={16} />
          <span>{students.length} Registered</span>
        </div>
      </header>

      {/* Main */}
      <main className="page-content">
        {/* Registration Form */}
        <section className="form-card card">
          <div className="card-heading">
            <div className="heading-icon">
              <UserPlus size={19} />
            </div>

            <div>
              <h2>Student Registration</h2>
              <p>Add a new student to the system</p>
            </div>
          </div>

          <form onSubmit={handleSubmit}>
            {/* Name */}
            <div className="field">
              <label htmlFor="name">Name</label>

              <input
                id="name"
                name="name"
                type="text"
                value={form.name}
                onChange={handleChange}
                placeholder="Enter student name"
                autoComplete="off"
                maxLength={100}
              />
            </div>

            {/* Roll */}
            <div className="field">
              <label htmlFor="roll">Roll</label>

              <input
                id="roll"
                name="roll"
                type="text"
                value={form.roll}
                onChange={handleChange}
                placeholder="Enter roll number"
                autoComplete="off"
                maxLength={30}
              />
            </div>

            {/* Department */}
            <div className="field">
              <label htmlFor="department">Department</label>

              <select
                id="department"
                name="department"
                value={form.department}
                onChange={handleChange}
              >
                <option value="">Select department</option>
                <option value="CSE">CSE</option>
                <option value="EEE">EEE</option>
                <option value="ECE">ECE</option>
              </select>
            </div>

            {/* Year */}
            <div className="field">
              <label htmlFor="year">Year</label>

              <input
                id="year"
                name="year"
                type="number"
                min="1900"
                max="2100"
                value={form.year}
                onChange={handleChange}
                placeholder="e.g. 2026"
              />
            </div>

            {/* Error */}
            {error && (
              <div className="message error">
                {error}
              </div>
            )}

            {/* Success */}
            {success && (
              <div className="message success">
                <CheckCircle2 size={16} />
                {success}
              </div>
            )}

            {/* Submit */}
            <button
              className="primary-btn"
              type="submit"
              disabled={submitting}
            >
              <UserPlus size={17} />

              {submitting
                ? "Registering..."
                : "Register Student"}
            </button>
          </form>
        </section>

        {/* Student Table */}
        <section className="table-card card">
          <div className="table-heading">
            <div>
              <h2>Registered Student Information</h2>
              <p>All registered students are listed below</p>
            </div>

            <span className="total-badge">
              {students.length}
            </span>
          </div>

          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Roll</th>
                  <th>Department</th>
                  <th>Year</th>
                  <th className="action-column">Action</th>
                </tr>
              </thead>

              <tbody>
                {/* Loading */}
                {loading ? (
                  <tr>
                    <td
                      className="empty-state"
                      colSpan="5"
                    >
                      Loading students...
                    </td>
                  </tr>
                ) : students.length === 0 ? (
                  /* Empty */
                  <tr>
                    <td
                      className="empty-state"
                      colSpan="5"
                    >
                      No students registered yet.
                    </td>
                  </tr>
                ) : (
                  /* Students */
                  students.map((student) => (
                    <tr key={student.id}>
                      <td className="student-name">
                        {student.name}
                      </td>

                      <td>{student.roll}</td>

                      <td>
                        <span className="department-badge">
                          {student.department}
                        </span>
                      </td>

                      <td>{student.year}</td>

                      <td className="action-cell">
                        <button
                          className="icon-btn"
                          title="Delete student"
                          onClick={() =>
                            handleDelete(student.id)
                          }
                          aria-label={`Delete ${student.name}`}
                          disabled={deletingId === student.id}
                        >
                          <Trash2 size={16} />
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </section>
      </main>
    </div>
  );
}

export default App;
