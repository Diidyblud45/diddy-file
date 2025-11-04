"""Simple GUI calculator implemented in a single file using tkinter."""

import ast
import operator
from functools import partial

import tkinter as tk
from tkinter import messagebox


class Calculator(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Calculator")
        self.resizable(False, False)
        self._create_widgets()

    def _create_widgets(self) -> None:
        self.display_var = tk.StringVar()

        display = tk.Entry(
            self,
            textvariable=self.display_var,
            font=("Arial", 20),
            justify="right",
            bd=10,
            relief=tk.FLAT,
            width=18,
        )
        display.grid(row=0, column=0, columnspan=4, padx=10, pady=(10, 5), sticky="nsew")

        button_rows = [
            [
                ("C", self._clear),
                ("DEL", self._backspace),
                ("%", self._percent),
                ("+/-", self._negate),
            ],
            [
                ("7", partial(self._append, "7")),
                ("8", partial(self._append, "8")),
                ("9", partial(self._append, "9")),
                ("/", partial(self._append, "/")),
            ],
            [
                ("4", partial(self._append, "4")),
                ("5", partial(self._append, "5")),
                ("6", partial(self._append, "6")),
                ("*", partial(self._append, "*")),
            ],
            [
                ("1", partial(self._append, "1")),
                ("2", partial(self._append, "2")),
                ("3", partial(self._append, "3")),
                ("-", partial(self._append, "-")),
            ],
            [
                ("0", partial(self._append, "0")),
                (".", partial(self._append, ".")),
                ("=", self._calculate),
                ("+", partial(self._append, "+")),
            ],
        ]

        for row_index, row_values in enumerate(button_rows, start=1):
            for col_index, (label, command) in enumerate(row_values):
                button = tk.Button(
                    self,
                    text=label,
                    font=("Arial", 16),
                    width=4,
                    height=2,
                    command=command,
                )
                button.grid(row=row_index, column=col_index, padx=5, pady=5, sticky="nsew")

        for row in range(len(button_rows) + 1):
            self.rowconfigure(row, weight=1)
        for col in range(4):
            self.columnconfigure(col, weight=1)

        self.bind("<Return>", lambda event: self._calculate())
        self.bind("<BackSpace>", lambda event: self._backspace())
        self.bind("<Escape>", lambda event: self._clear())

    def _append(self, char: str) -> None:
        current = self.display_var.get()
        self.display_var.set(current + char)

    def _clear(self) -> None:
        self.display_var.set("")

    def _backspace(self) -> None:
        current = self.display_var.get()
        if current:
            self.display_var.set(current[:-1])

    def _negate(self) -> None:
        current = self.display_var.get()
        if not current:
            return
        try:
            value = self._safe_evaluate(current)
        except ValueError as error:
            messagebox.showerror("Error", str(error))
            return
        self.display_var.set(self._format_number(-value))

    def _percent(self) -> None:
        current = self.display_var.get()
        if not current:
            return
        try:
            value = self._safe_evaluate(current)
        except ValueError as error:
            messagebox.showerror("Error", str(error))
            return
        self.display_var.set(self._format_number(value / 100))

    def _calculate(self) -> None:
        expression = self.display_var.get()
        if not expression:
            return
        try:
            result = self._safe_evaluate(expression)
        except ValueError as error:
            messagebox.showerror("Error", str(error))
            return
        self.display_var.set(self._format_number(result))

    def _safe_evaluate(self, expression: str) -> float:
        try:
            node = ast.parse(expression, mode="eval")
        except SyntaxError as error:
            raise ValueError("Invalid expression") from error

        def _eval(node: ast.AST) -> float:
            if isinstance(node, ast.Expression):
                return _eval(node.body)
            if isinstance(node, ast.Constant):
                if isinstance(node.value, (int, float)):
                    return float(node.value)
                raise ValueError("Only numbers allowed")
            if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
                operand = _eval(node.operand)
                op_map = {ast.UAdd: operator.pos, ast.USub: operator.neg}
                return float(op_map[type(node.op)](operand))
            if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
                left = _eval(node.left)
                right = _eval(node.right)
                op_map = {
                    ast.Add: operator.add,
                    ast.Sub: operator.sub,
                    ast.Mult: operator.mul,
                    ast.Div: operator.truediv,
                }
                try:
                    return float(op_map[type(node.op)](left, right))
                except ZeroDivisionError as error:
                    raise ValueError("Cannot divide by zero") from error
            raise ValueError("Invalid expression")

        return _eval(node)

    def _format_number(self, value: float) -> str:
        if value.is_integer():
            return str(int(value))
        return str(value)


def main() -> None:
    app = Calculator()
    app.mainloop()


if __name__ == "__main__":
    main()
