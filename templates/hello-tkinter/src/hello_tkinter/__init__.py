import tkinter as tk


def hello() -> None:
    root = tk.Tk()
    root.title("Hello Tkinter")
    tk.Label(root, text="Hello from hello-tkinter!").pack()
    root.mainloop()
