package com.example.raspisanie.adapter

import android.content.Context
import android.graphics.Typeface
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.example.raspisanie.R
import com.example.raspisanie.data.Group
import com.google.android.material.color.MaterialColors

/**
 * Улучшенный адаптер для Spinner групп с красивым дизайном и поддержкой избранных
 */
class GroupsSpinnerAdapter(
    context: Context,
    private val groups: List<Group>,
    private val favoriteGroups: Set<String>
) : ArrayAdapter<Group>(context, R.layout.item_group_spinner, groups) {
    
    private val colorPrimary = MaterialColors.getColor(context, com.google.android.material.R.attr.colorPrimary, "GroupsSpinnerAdapter")
    private val textColorPrimary = MaterialColors.getColor(context, android.R.attr.textColorPrimary, "GroupsSpinnerAdapter")
    private val textColorSecondary = MaterialColors.getColor(context, android.R.attr.textColorSecondary, "GroupsSpinnerAdapter")
    private val colorDarkerGray = ContextCompat.getColor(context, android.R.color.darker_gray)
    
    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view = convertView ?: LayoutInflater.from(context)
            .inflate(R.layout.item_group_spinner, parent, false)
        
        val groupName = view.findViewById<TextView>(R.id.groupName)
        val groupIcon = view.findViewById<TextView>(R.id.groupIcon)
        val group = getItem(position)!!
        
        if (group.name.isEmpty()) {
            // "Группа не выбрана"
            groupName.text = group.name
            groupIcon.visibility = View.GONE
            groupName.setTextColor(colorDarkerGray)
        } else if (favoriteGroups.contains(group.name)) {
            // Избранная группа
            groupName.text = group.name
            groupIcon.text = "⭐"
            groupIcon.visibility = View.VISIBLE
            groupName.setTypeface(null, Typeface.BOLD)
            groupName.setTextColor(colorPrimary)
        } else {
            // Обычная группа
            groupName.text = group.name
            groupIcon.visibility = View.GONE
            groupName.setTypeface(null, Typeface.NORMAL)
            groupName.setTextColor(textColorPrimary)
        }
        
        return view
    }
    
    override fun getDropDownView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view = convertView ?: LayoutInflater.from(context)
            .inflate(R.layout.item_group_spinner_dropdown, parent, false)
        
        val groupName = view.findViewById<TextView>(R.id.groupName)
        val groupFileName = view.findViewById<TextView>(R.id.groupFileName)
        val groupIcon = view.findViewById<TextView>(R.id.groupIcon)
        val favoriteIcon = view.findViewById<TextView>(R.id.favoriteIcon)
        val group = getItem(position)!!
        
        // Разделитель для избранных групп
        var isFavorite = false
        var isFirstFavorite = false
        
        if (group.name.isNotEmpty() && favoriteGroups.contains(group.name)) {
            val favoriteIndex = groups.indexOfFirst { 
                it.name.isNotEmpty() && favoriteGroups.contains(it.name) 
            }
            isFirstFavorite = (position == favoriteIndex + 1) // +1 из-за "Группа не выбрана"
            isFavorite = true
        }
        
        if (group.name.isEmpty()) {
            // "Группа не выбрана"
            groupName.text = group.name
            groupFileName.visibility = View.GONE
            groupIcon.visibility = View.GONE
            favoriteIcon.visibility = View.GONE
            groupName.setTextColor(colorDarkerGray)
            view.setPadding(view.paddingLeft, view.paddingTop + if (position == 0) 0 else 8, view.paddingRight, view.paddingBottom)
        } else if (isFavorite) {
            // Избранная группа
            groupName.text = group.name
            groupFileName.visibility = View.GONE
            groupIcon.text = "⭐"
            groupIcon.visibility = View.VISIBLE
            favoriteIcon.visibility = View.VISIBLE
            groupName.setTypeface(null, Typeface.BOLD)
            groupName.setTextColor(colorPrimary)
            
            // Добавляем отступ сверху для первой избранной группы
            view.setPadding(
                view.paddingLeft,
                view.paddingTop + if (isFirstFavorite) 8 else 0,
                view.paddingRight,
                view.paddingBottom
            )
        } else {
            // Обычная группа
            groupName.text = group.name
            groupFileName.visibility = View.GONE
            groupIcon.visibility = View.GONE
            favoriteIcon.visibility = View.GONE
            groupName.setTypeface(null, Typeface.NORMAL)
            groupName.setTextColor(textColorPrimary)
            
            // Проверяем, не первая ли это обычная группа после избранных
            val firstRegularIndex = groups.indexOfFirst { 
                it.name.isNotEmpty() && !favoriteGroups.contains(it.name) 
            }
            val isFirstRegular = (position == firstRegularIndex + favoriteGroups.size + 1) // +1 из-за "Группа не выбрана"
            view.setPadding(
                view.paddingLeft,
                view.paddingTop + if (isFirstRegular && favoriteGroups.isNotEmpty()) 8 else 0,
                view.paddingRight,
                view.paddingBottom
            )
        }
        
        return view
    }
}
