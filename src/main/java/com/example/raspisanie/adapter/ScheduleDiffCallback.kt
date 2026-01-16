package com.example.raspisanie.adapter

import androidx.recyclerview.widget.DiffUtil
import com.example.raspisanie.data.DaySchedule

/**
 * DiffUtil Callback для анимаций появления/исчезновения дней в расписании
 */
class ScheduleDiffCallback(
    private val oldList: List<DaySchedule>,
    private val newList: List<DaySchedule>
) : DiffUtil.Callback() {

    override fun getOldListSize(): Int = oldList.size

    override fun getNewListSize(): Int = newList.size

    override fun areItemsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
        val oldSchedule = oldList[oldItemPosition]
        val newSchedule = newList[newItemPosition]
        // Сравниваем по дате - если дата совпадает, это тот же день
        return oldSchedule.date == newSchedule.date
    }

    override fun areContentsTheSame(oldItemPosition: Int, newItemPosition: Int): Boolean {
        val oldSchedule = oldList[oldItemPosition]
        val newSchedule = newList[newItemPosition]
        // Сравниваем содержимое дней
        return oldSchedule == newSchedule
    }

    override fun getChangePayload(oldItemPosition: Int, newItemPosition: Int): Any? {
        // Возвращаем null, чтобы использовать полную анимацию
        return null
    }
}
