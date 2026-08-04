from airflow.sdk import dag, task
from airflow.providers.standard.operators.bash import BashOperator

@dag(schedule='* * * * *')
def dag_00_example():
    @task
    def python_task():
        print('this is python_task')

    @task.bash
    def bash_task_1():
        return 'echo "this is bash_task_1"'

    bash_task_2 = BashOperator(
        task_id='bash_task_2',
        bash_command='echo "this is bash_task_2"'
    )

    python_task() >> [bash_task_1(), bash_task_2]

dag_00_example()
